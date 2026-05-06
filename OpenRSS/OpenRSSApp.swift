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
import CryptoKit
import Combine

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
            ArticleState.self,
            UserPreferences.self,
        ])

        // Check Keychain directly — AuthenticationManager isn't configured yet.
        // If an Apple user ID is stored, the user was previously signed in.
        var isSignedIn = KeychainService.loadAppleUserID() != nil

        // Disable CloudKit on simulator/DEBUG builds so local development never
        // blocks on CloudKit sync round-trips. Production device builds keep
        // the original behavior: enable CloudKit when the user is signed in.
        #if targetEnvironment(simulator) || DEBUG
        let cloudKitDB: ModelConfiguration.CloudKitDatabase = .none
        #else
        let cloudKitDB: ModelConfiguration.CloudKitDatabase = isSignedIn ? .automatic : .none
        #endif

        let config = ModelConfiguration(
            schema: schema,
            cloudKitDatabase: cloudKitDB
        )

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
                print("⚠️ CloudKit-enabled container still failing — falling back to local-only: \(error)")
                isSignedIn = false
                let localConfig = ModelConfiguration(
                    schema: schema,
                    cloudKitDatabase: .none
                )
                do {
                    container = try ModelContainer(for: schema, configurations: localConfig)
                } catch {
                    fatalError("Failed to create local-only SwiftData ModelContainer: \(error)")
                }
            }
        }

        // Bootstrap the shared service with the container's main context.
        // @main App.init() is always called on the main thread, so assumeIsolated is safe.
        MainActor.assumeIsolated {
            SwiftDataService.shared.configure(container: container)
            AuthenticationManager.shared.configure(container: container)

            // Pre-warm the WKWebView pool so the first article open is fast.
            WebViewPool.shared.warmUp()

            SyncService.shared.startMonitoring(isCloudKitEnabled: isSignedIn)
        }

        // Phase 2a — Register BGTask for background river refresh
        Self.registerBackgroundTasks()
    }

    // MARK: - Background Task Registration

    private static let riverRefreshIdentifier = "com.openrss.riverRefresh"
    /// Long-tail hero pre-fetch. Runs as a BGProcessingTask so the system can
    /// pick a window when the device is on a charger and on Wi-Fi (typically
    /// overnight) and we have a much larger runtime budget than a refresh task.
    private static let heroPrefetchIdentifier = "com.openrss.heroPrefetch"

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

        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: heroPrefetchIdentifier,
            using: nil
        ) { task in
            guard let bgTask = task as? BGProcessingTask else {
                task.setTaskCompleted(success: false)
                return
            }
            handleHeroPrefetch(task: bgTask)
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

            // Pre-warm hero thumbnails for the top of the freshly-ingested
            // river so the user's first scroll on next foreground paints from
            // disk. Tight 8s budget keeps us comfortably inside the ~30s
            // BGAppRefreshTask window.
            await prewarmTopHeroes(count: 10, budgetSeconds: 8)

            task.setTaskCompleted(success: true)
        }

        // If the system kills the background task, cancel our work
        task.expirationHandler = {
            workTask.cancel()
        }
    }

    /// Pulls the latest snapshot from the pipeline and warms hero thumbnails
    /// for the top-N items via HeroPrefetcher. Used by both background tasks.
    /// Falls back to the SQLiteStore directly if no snapshot has been emitted
    /// yet (e.g. very first launch into background refresh).
    private static func prewarmTopHeroes(
        skip: Int = 0,
        count: Int,
        budgetSeconds: TimeInterval
    ) async {
        let snapshot = RiverPipeline.shared.snapshotPublisher.value
        let slice = snapshot.items.dropFirst(skip).prefix(count)
        guard !slice.isEmpty else { return }

        var inputs: [HeroInput] = []
        inputs.reserveCapacity(slice.count)
        for item in slice {
            switch item {
            case .article(let f):
                inputs.append(HeroInput(pageURL: f.link.absoluteString, imageURL: f.imageURL))
            case .cluster(let c):
                inputs.append(
                    HeroInput(
                        pageURL: c.canonicalItem.link.absoluteString,
                        imageURL: c.canonicalItem.imageURL
                    )
                )
            case .digest, .nudge:
                continue
            }
        }
        guard !inputs.isEmpty else { return }
        await HeroPrefetcher.warm(inputs: inputs, budgetSeconds: budgetSeconds)
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

    // MARK: - Hero Pre-Fetch (Long Tail)

    /// Handles the long-tail hero thumbnail pre-fetch task.
    /// Warms items 11..50 of the latest river snapshot so the user can scroll
    /// deep into the feed without ever waiting on hero downloads. Constrained
    /// to charger + Wi-Fi via the BGProcessingTaskRequest so it doesn't burn
    /// cellular data or battery.
    private static func handleHeroPrefetch(task: BGProcessingTask) {
        // Schedule the next one before doing work so we keep the cadence even
        // if this run is killed.
        scheduleNextHeroPrefetch()

        let workTask = Task {
            guard await isNetworkAvailable() else {
                task.setTaskCompleted(success: false)
                return
            }
            // Generous budget — well under the BGProcessingTask cap (~30 min)
            // but long enough to download ~40 thumbnails on a slow link.
            await prewarmTopHeroes(skip: 10, count: 40, budgetSeconds: 90)
            task.setTaskCompleted(success: true)
        }

        task.expirationHandler = {
            workTask.cancel()
        }
    }

    /// Schedules the next BGProcessingTask request for hero pre-fetch.
    /// `requiresExternalPower = true` and `requiresNetworkConnectivity = true`
    /// so the OS only fires us when the user is plugged in on Wi-Fi —
    /// typically overnight at the charging cable.
    static func scheduleNextHeroPrefetch() {
        // Honor the user's manual-refresh preference: if they don't want any
        // background work, don't schedule the long-tail warm either.
        guard RefreshStateStore.shared.refreshInterval != .manual else { return }

        let request = BGProcessingTaskRequest(identifier: heroPrefetchIdentifier)
        request.requiresExternalPower = true
        request.requiresNetworkConnectivity = true
        // Earliest begin: ~6 hours from now, so the OS picks a quiet moment
        // (often the next overnight charging window) to actually run us.
        request.earliestBeginDate = Date(timeIntervalSinceNow: 6 * 60 * 60)

        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            print("BGProcessingTask (heroPrefetch) scheduling failed: \(error)")
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
                .onAppear {
                    // Sync persisted preferences into AppState so all views
                    // start with the correct values without needing @Query.
                    let prefs = SwiftDataService.shared.userPreferences()
                    appState.showImages = prefs.showImages
                }
                .onReceive(
                    NotificationCenter.default.publisher(
                        for: UIApplication.didReceiveMemoryWarningNotification
                    )
                ) { _ in
                    URLCache.shared.removeAllCachedResponses()
                }
                // Schedule background refresh + hero pre-fetch when the app
                // moves to background. Keeping these submissions co-located
                // makes it obvious that both cadences are tied to the same
                // user action (sending the app to background).
                .onReceive(
                    NotificationCenter.default.publisher(
                        for: UIApplication.didEnterBackgroundNotification
                    )
                ) { _ in
                    Self.scheduleNextRiverRefresh()
                    Self.scheduleNextHeroPrefetch()
                }
                .onReceive(
                    NotificationCenter.default.publisher(
                        for: Notification.Name("OpenRSS.AuthStateChanged")
                    )
                ) { _ in
                    let isNowSignedIn = AuthenticationManager.shared.isSignedIn
                    SyncService.shared.startMonitoring(isCloudKitEnabled: isNowSignedIn)
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
