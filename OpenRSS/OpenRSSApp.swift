//
//  OpenRSSApp.swift
//  OpenRSS
//
//  Created by Darius Ehsani on 2/3/26.
//

import SwiftUI
import SwiftData
import UIKit
import BackgroundTasks

@main
struct OpenRSSApp: App {

    // MARK: - SwiftData ModelContainer

    let container: ModelContainer

    init() {
        // Bound the shared URLCache so AsyncImage doesn't accumulate images
        // in memory indefinitely as the user scrolls.
        URLCache.shared = URLCache(
            memoryCapacity:  30 * 1024 * 1024,   // 30 MB in-memory
            diskCapacity:   100 * 1024 * 1024,    // 100 MB on-disk
            directory: nil                         // default location
        )

        let schema = Schema([FolderModel.self, FeedModel.self, CachedArticle.self])
        let config = ModelConfiguration(schema: schema)

        do {
            container = try ModelContainer(for: schema, configurations: config)
        } catch {
            // Schema changed and lightweight migration failed (common during development).
            // Wipe all store files and recreate a clean container.
            // User data (folders/feeds) will be lost but can be re-added.
            print("⚠️ SwiftData migration failed — wiping store: \(error)")
            let storeURL  = config.url
            let storeDir  = storeURL.deletingLastPathComponent()
            let storeName = storeURL.lastPathComponent
            if let files = try? FileManager.default.contentsOfDirectory(
                at: storeDir, includingPropertiesForKeys: nil
            ) {
                for file in files where file.lastPathComponent.hasPrefix(storeName) {
                    try? FileManager.default.removeItem(at: file)
                }
            }
            do {
                container = try ModelContainer(for: schema, configurations: config)
            } catch {
                fatalError("Failed to recreate SwiftData ModelContainer: \(error)")
            }
        }

        // Bootstrap the shared service with the container's main context.
        // @main App.init() is always called on the main thread, so assumeIsolated is safe.
        MainActor.assumeIsolated {
            SwiftDataService.shared.configure(container: container)

            // Pre-warm the WKWebView pool so the first article open is fast.
            WebViewPool.shared.warmUp()
        }

        // Phase 2a — Register BGTask for background river refresh
        Self.registerBackgroundTasks()
    }

    // MARK: - Background Task Registration

    private static let riverRefreshIdentifier = "com.openrss.riverRefresh"

    private static func registerBackgroundTasks() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: riverRefreshIdentifier,
            using: nil
        ) { task in
            guard let bgTask = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            handleRiverRefresh(task: bgTask)
        }
    }

    private static func handleRiverRefresh(task: BGAppRefreshTask) {
        // Schedule the next refresh before starting work
        scheduleNextRiverRefresh()

        let workTask = Task {
            let sources = await MainActor.run { SwiftDataService.shared.sources }
            await RiverPipeline.shared.runCycle(sources: sources)
            task.setTaskCompleted(success: true)
        }

        // If the system kills the background task, cancel our work
        task.expirationHandler = {
            workTask.cancel()
        }
    }

    /// Schedules the next background river refresh.
    static func scheduleNextRiverRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: riverRefreshIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 30 * 60) // 30 minutes
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            print("BGTask scheduling failed: \(error)")
        }
    }

    // MARK: - App State

    @State private var appState = AppState()

    // MARK: - Body

    var body: some Scene {
        WindowGroup {
            MainTabView()
                .environment(appState)
                .onReceive(
                    NotificationCenter.default.publisher(
                        for: UIApplication.didReceiveMemoryWarningNotification
                    )
                ) { _ in
                    URLCache.shared.removeAllCachedResponses()
                }
                // Schedule background refresh when the app moves to background
                .onReceive(
                    NotificationCenter.default.publisher(
                        for: UIApplication.didEnterBackgroundNotification
                    )
                ) { _ in
                    Self.scheduleNextRiverRefresh()
                }
        }
        .modelContainer(container)
    }
}
