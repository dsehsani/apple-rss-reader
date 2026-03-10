//
//  OpenRSSApp.swift
//  OpenRSS
//
//  Created by Darius Ehsani on 2/3/26.
//

import SwiftUI
import SwiftData

@main
struct OpenRSSApp: App {

    // MARK: - SwiftData ModelContainer

    let container: ModelContainer

    init() {
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
    }

    // MARK: - App State

    @State private var appState = AppState()

    // MARK: - Body

    var body: some Scene {
        WindowGroup {
            MainTabView()
                .environment(appState)
        }
        .modelContainer(container)
    }
}
