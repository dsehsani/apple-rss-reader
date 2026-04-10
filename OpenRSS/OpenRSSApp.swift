//
//  OpenRSSApp.swift
//  OpenRSS
//
//  Created by Darius Ehsani on 2/3/26.
//

import SwiftUI
import SwiftData
import UIKit

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

        // Bootstrap the shared services with the container's main context.
        // @main App.init() is always called on the main thread, so assumeIsolated is safe.
        MainActor.assumeIsolated {
            SwiftDataService.shared.configure(container: container)
            AuthenticationManager.shared.configure(container: container)

            // Pre-warm the WKWebView pool so the first article open is fast.
            WebViewPool.shared.warmUp()
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
    /// - `.unknown` → brief splash/loading (auth check in progress)
    /// - `.signedOut` + never skipped → OnboardingView
    /// - `.signedOut` + skipped (guest) → MainTabView
    /// - `.signedIn` → MainTabView
    @ViewBuilder
    private var rootView: some View {
        let auth = AuthenticationManager.shared

        switch auth.state {
        case .unknown:
            // Auth check is in-flight. Show a minimal loading state
            // so the UI doesn't flash onboarding for signed-in users.
            Color.clear

        case .signedOut:
            if auth.shouldShowOnboarding {
                OnboardingView()
            } else {
                MainTabView()
            }

        case .signedIn:
            MainTabView()
        }
    }
}
