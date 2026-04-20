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
import Network

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

        let schema = Schema([
            FolderModel.self,
            FeedModel.self,
            CachedArticle.self,
            UserProfile.self,
        ])
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
            AuthenticationManager.shared.configure(container: container)

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
            // Network check — skip the pipeline if there is no connection
            guard await isNetworkAvailable() else {
                print("BGTask: skipping refresh — no network")
                task.setTaskCompleted(success: false)
                return
            }

            let sources = await MainActor.run { SwiftDataService.shared.sources }

            // Snapshot count before
            let countBefore = SQLiteStore.shared.totalItemCount()

            await RiverPipeline.shared.runCycle(sources: sources)

            // Snapshot count after — detect empty cycle
            let countAfter = SQLiteStore.shared.totalItemCount()
            let store = RefreshStateStore.shared
            if countAfter > countBefore {
                store.consecutiveEmptyRefreshes = 0
            } else {
                store.consecutiveEmptyRefreshes += 1
            }

            store.lastRefreshedAt = Date()

            task.setTaskCompleted(success: true)
        }

        // If the system kills the background task, cancel our work
        task.expirationHandler = {
            workTask.cancel()
        }
    }

    /// Returns true if the device has any usable network path.
    private static func isNetworkAvailable() async -> Bool {
        await withCheckedContinuation { continuation in
            let monitor = NWPathMonitor()
            let queue = DispatchQueue(label: "com.openrss.networkCheck")
            monitor.pathUpdateHandler = { path in
                monitor.cancel()
                continuation.resume(returning: path.status == .satisfied)
            }
            monitor.start(queue: queue)
        }
    }

    /// Schedules the next background river refresh.
    static func scheduleNextRiverRefresh() {
        let interval = RefreshStateStore.shared.nextIntervalSeconds
        guard interval.isFinite else { return }  // .manual — do not schedule

        let request = BGAppRefreshTaskRequest(identifier: riverRefreshIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: interval)
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            print("BGTask scheduling failed: \(error)")
        }
    }

    // MARK: - App State

    @State private var appState = AppState()
    @State private var hasCheckedAuth = false

    // MARK: - Body

    var body: some Scene {
        WindowGroup {
            rootView
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
                .task {
                    guard !hasCheckedAuth else { return }
                    hasCheckedAuth = true
                    await AuthenticationManager.shared.checkExistingCredential()
                }
        }
        .modelContainer(container)
    }

    // MARK: - Root View

    /// Decides whether to show onboarding or the main app.
    ///
    /// - `.unknown`   → blank screen (auth check in-flight, prevents onboarding flash)
    /// - `.signedOut` + never skipped → OnboardingView
    /// - `.signedOut` + guest mode    → MainTabView
    /// - `.signedIn`  → MainTabView
    @ViewBuilder
    private var rootView: some View {
        let auth = AuthenticationManager.shared

        switch auth.state {
        case .unknown:
            Color.clear

        case .signedOut:
            if auth.shouldShowOnboarding {
                OnboardingView()
            } else {
                mainApp
            }

        case .signedIn:
            mainApp
        }
    }

    private var mainApp: some View {
        MainTabView()
    }
}
