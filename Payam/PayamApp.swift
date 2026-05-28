//
//  PayamApp.swift
//  Payam
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
struct PayamApp: App {

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
            FilterRuleModel.self,
        ])

        // Check Keychain directly — AuthenticationManager isn't configured yet.
        // If an Apple user ID is stored, the user was previously signed in.
        let isSignedIn = KeychainService.loadAppleUserID() != nil

        // Read isPremium from UserDefaults — SwiftData isn't ready yet.
        // Default true so new installs start on Premium.
        let isPremium = UserDefaults.standard.object(forKey: "payam.isPremium") as? Bool ?? true

        // Disable CloudKit on simulator/DEBUG builds so local development never
        // blocks on CloudKit sync round-trips. Production device builds enable
        // CloudKit only when the user is signed in and on Premium (Basic mode
        // skips all cloud services including CloudKit).
        #if targetEnvironment(simulator) || DEBUG
        let wantsCloudKit = false
        #else
        let wantsCloudKit = isSignedIn && isPremium
        #endif

        // Open the store through a non-destructive recovery ladder (retry, then
        // a CloudKit-off open of the SAME file) so a transient open failure
        // after an out-of-memory kill never deletes the user's feeds/folders.
        // CloudKit is treated as active only if the store actually opened with it.
        let result = Self.makeContainer(schema: schema, wantsCloudKit: wantsCloudKit)
        container = result.container
        let cloudKitActive = result.cloudKitActive

        // Bootstrap the shared service with the container's main context.
        // @main App.init() is always called on the main thread, so assumeIsolated is safe.
        MainActor.assumeIsolated {
            SwiftDataService.shared.configure(container: container)
            AuthenticationManager.shared.configure(container: container)

            // Pre-warm the WKWebView pool so the first article open is fast.
            WebViewPool.shared.warmUp()

            SyncService.shared.startMonitoring(isCloudKitEnabled: cloudKitActive)

            // If the store had to be wiped as a true last resort, repopulate
            // feeds/folders from the OPML backup written just before the wipe.
            Self.restoreFromOPMLBackupIfNeeded()
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

            let (sources, filterRules, sourceFilterMeta) = await MainActor.run {
                let sources = SwiftDataService.shared.sources
                let rules = SwiftDataService.shared.loadFilterRuleSnapshots()
                let folderNameByID = Dictionary(
                    uniqueKeysWithValues: SwiftDataService.shared.categories.map { ($0.id, $0.name) }
                )
                let meta: [UUID: (feedURL: String, folderName: String?)] = Dictionary(
                    uniqueKeysWithValues: sources.map { ($0.id, ($0.feedURL, folderNameByID[$0.categoryID])) }
                )
                return (sources, rules, meta)
            }

            // Snapshot count before
            let countBefore = SQLiteStore.shared.totalItemCount()

            _ = await RiverPipeline.shared.runCycle(
                sources: sources,
                filterRules: filterRules,
                sourceFilterMeta: sourceFilterMeta
            )

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

    // MARK: - Store Recovery

    /// UserDefaults flag set the moment the store is wiped as a last resort, and
    /// cleared only after the OPML backup has been fully re-imported. Tying
    /// recovery to this one-shot flag (rather than "the store is empty") avoids
    /// resurrecting feeds a user deliberately deleted and avoids re-importing on
    /// every launch.
    static let pendingOPMLRecoveryKey = "payam.pendingOPMLRecovery"

    private struct ContainerResult {
        let container: ModelContainer
        let cloudKitActive: Bool
    }

    /// Opens the SwiftData store through a non-destructive recovery ladder and,
    /// only as an absolute last resort, backs up + wipes + recreates it.
    ///
    /// Order (stops at the first success):
    ///   1–2. Requested config (CloudKit on/off), with one brief retry for
    ///        transient `-wal`/`-shm` sidecar contention after an abrupt kill.
    ///   3.   CloudKit-off open of the SAME file — non-destructive, keeps all
    ///        local data, only disables sync for this session.
    ///   4.   Genuine corruption only: OPML backup → flag → wipe → fresh store
    ///        (falling back to an in-memory store rather than crashing).
    private static func makeContainer(schema: Schema, wantsCloudKit: Bool) -> ContainerResult {
        let primaryConfig = ModelConfiguration(
            schema: schema,
            cloudKitDatabase: wantsCloudKit ? .automatic : .none
        )

        // 1 + 2. Try the requested config, with a brief retry. An OOM kill is a
        // SIGKILL with no clean flush, so the next cold open can fail transiently.
        for attempt in 0..<2 {
            do {
                let c = try ModelContainer(for: schema, configurations: primaryConfig)
                return ContainerResult(container: c, cloudKitActive: wantsCloudKit)
            } catch {
                print("⚠️ SwiftData open failed (attempt \(attempt + 1), cloudKit=\(wantsCloudKit)): \(error)")
                if attempt == 0 { Thread.sleep(forTimeInterval: 0.2) }
            }
        }

        // 3. Non-destructive CloudKit-off retry on the SAME store. Opening the
        // existing file without CloudKit mirroring preserves all local data and
        // only disables sync for this session (it re-attaches next clean launch).
        // Skip if we already opened CloudKit-off above.
        let localConfig = ModelConfiguration(schema: schema, cloudKitDatabase: .none)
        if wantsCloudKit {
            do {
                let c = try ModelContainer(for: schema, configurations: localConfig)
                print("⚠️ Opened store with CloudKit disabled — data preserved, sync inactive this session")
                return ContainerResult(container: c, cloudKitActive: false)
            } catch {
                print("⚠️ CloudKit-off open of existing store also failed: \(error)")
            }
        }

        // 4. True last resort: the store is genuinely unopenable. Back it up to
        // OPML, flag for auto-restore, wipe, and recreate an empty store.
        print("⛔️ Store unopenable by any config — backing up and wiping as a last resort")
        emergencyOPMLExport(schema: schema)
        UserDefaults.standard.set(true, forKey: pendingOPMLRecoveryKey)
        wipeStoreFiles(at: localConfig.url)

        if let c = try? ModelContainer(for: schema, configurations: localConfig) {
            return ContainerResult(container: c, cloudKitActive: false)
        }

        // Absolute final guard: an in-memory store so the app at least launches.
        do {
            let memConfig = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            let c = try ModelContainer(for: schema, configurations: memConfig)
            print("⛔️ Falling back to in-memory store — data will not persist this session")
            return ContainerResult(container: c, cloudKitActive: false)
        } catch {
            fatalError("Failed to create any SwiftData ModelContainer: \(error)")
        }
    }

    /// Removes the SQLite store file and its `-wal`/`-shm` sidecars.
    private static func wipeStoreFiles(at storeURL: URL) {
        let storeDir  = storeURL.deletingLastPathComponent()
        let storeName = storeURL.lastPathComponent
        if let files = try? FileManager.default.contentsOfDirectory(
            at: storeDir, includingPropertiesForKeys: nil
        ) {
            for file in files where file.lastPathComponent.hasPrefix(storeName) {
                try? FileManager.default.removeItem(at: file)
            }
        }
    }

    /// Location of the OPML safety copy written before a last-resort wipe. Shared
    /// by the export and the auto-restore so they always agree on the path.
    static var recoveryBackupURL: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docs.appendingPathComponent("payam-recovery-backup.opml")
    }

    /// After a last-resort wipe, repopulate feeds/folders from the OPML backup.
    /// Runs only when the one-shot recovery flag is set; clears the flag only on
    /// a fully successful import so an interrupted restore is retried next launch
    /// (import skips duplicates by feedURL, so retries are idempotent).
    @MainActor
    private static func restoreFromOPMLBackupIfNeeded() {
        guard UserDefaults.standard.bool(forKey: pendingOPMLRecoveryKey) else { return }

        let backupURL = recoveryBackupURL
        guard FileManager.default.fileExists(atPath: backupURL.path) else {
            UserDefaults.standard.set(false, forKey: pendingOPMLRecoveryKey)
            return
        }

        Task { @MainActor in
            do {
                let result = try await OPMLService.shared.importFromURL(backupURL, into: .shared)
                print("✅ Auto-restored \(result.imported) feed(s) from recovery backup")
                UserDefaults.standard.set(false, forKey: pendingOPMLRecoveryKey)
            } catch {
                print("⚠️ OPML auto-restore failed, will retry next launch: \(error)")
            }
        }
    }

    // MARK: - Emergency OPML Backup

    /// Attempts to read folders and feeds from the existing (pre-wipe) store
    /// and write an OPML backup to Documents. Called before the store is wiped.
    /// Best-effort: if the old store is too corrupted to read, we skip silently.
    private static func emergencyOPMLExport(schema: Schema) {
        do {
            let readOnlyConfig = ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: false,
                cloudKitDatabase: .none
            )
            let oldContainer = try ModelContainer(
                for: FolderModel.self, FeedModel.self,
                configurations: readOnlyConfig
            )
            let context = ModelContext(oldContainer)
            context.autosaveEnabled = false

            let folders = (try? context.fetch(FetchDescriptor<FolderModel>())) ?? []
            let allFeeds = (try? context.fetch(FetchDescriptor<FeedModel>())) ?? []
            let folderedFeedIDs = Set(folders.flatMap { $0.feeds.map(\.id) })
            let unfiledFeeds = allFeeds.filter { !folderedFeedIDs.contains($0.id) }

            guard !folders.isEmpty || !unfiledFeeds.isEmpty else {
                print("⚠️ OPML backup: no feeds found in old store, skipping")
                return
            }

            let opmlURL = try OPMLService.shared.export(
                folders: folders,
                unfiledFeeds: unfiledFeeds
            )

            let backupURL = recoveryBackupURL
            try? FileManager.default.removeItem(at: backupURL)
            try FileManager.default.copyItem(at: opmlURL, to: backupURL)

            let count = folders.flatMap(\.feeds).count + unfiledFeeds.count
            print("✅ OPML backup saved (\(count) feeds) → \(backupURL.path)")
        } catch {
            print("⚠️ OPML backup failed (store too corrupted): \(error)")
        }
    }

    // MARK: - App State

    @State private var appState = AppState()

    // MARK: - Body

    var body: some Scene {
        WindowGroup {
            SplashGate(resolvedRoot: { rootView })
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
                    // Flush any pending main-context edits before the OS can
                    // suspend or memory-kill us. CRUD already saves via background
                    // contexts; this is low-risk insurance for main-context writes.
                    SwiftDataService.shared.saveMainContext()
                    Self.scheduleNextRiverRefresh()
                    Self.scheduleNextHeroPrefetch()
                }
                .onReceive(
                    NotificationCenter.default.publisher(
                        for: Notification.Name("Payam.AuthStateChanged")
                    )
                ) { _ in
                    let isNowSignedIn = AuthenticationManager.shared.isSignedIn
                    SyncService.shared.startMonitoring(isCloudKitEnabled: isNowSignedIn)
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
