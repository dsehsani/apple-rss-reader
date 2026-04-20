# Multi-Device Sync — CloudKit Implementation Guide

**Project:** OpenRSS (AppleRSS)
**Target:** iOS 17+, SwiftUI, SwiftData + CloudKit
**Prerequisite:** `feature/auth-phase1` merged into `main` (OnboardingMerge guide complete)
**Scope:** Phases 2 & 3 from the design doc — Sync Infrastructure + CloudKit Sync

---

## What This Guide Covers

Phase 1 (Sign in with Apple, `UserProfile`, `OnboardingView`) is complete via the auth branch. This guide picks up at Phase 2 and implements everything needed for real cross-device sync:

1. Two new SwiftData models: `ArticleState` and `UserPreferences`
2. Conditional `ModelContainer` configuration (CloudKit for signed-in, local for guest)
3. `SwiftDataService` updated to persist read/bookmark state through `ArticleState`
4. `SyncService` for monitoring CloudKit event status
5. `AccountView` wired with real sync status
6. `SettingsView` settings bound to `UserPreferences` model
7. Xcode capability: iCloud + CloudKit

---

## Architecture Summary

The core insight is that SwiftData's CloudKit integration (`cloudKitDatabase: .automatic`) does the heavy lifting — no custom `CKRecord` serialization, no subscription management. The only work is:

- Adding two new models for data that currently only lives in memory (`ArticleState`, `UserPreferences`)
- Switching the `ModelContainer` to use `.automatic` when a user is signed in
- Teaching `SwiftDataService` to write to `ArticleState` whenever read/bookmark state changes
- Handling conflict resolution for the one tricky case: `isRead` is monotonic (once true, always true)

---

## New Files to Create

```
OpenRSS/Models/ArticleState.swift
OpenRSS/Models/UserPreferences.swift
OpenRSS/Services/SyncService.swift
```

---

## Part 1: ArticleState.swift

Create at `OpenRSS/Models/ArticleState.swift`.

```swift
//
//  ArticleState.swift
//  OpenRSS
//
//  SwiftData model for synced per-article read/bookmark/paywall state.
//  Keyed by SHA-256 hash of the article URL for stable cross-device identity.
//

import Foundation
import SwiftData
import CryptoKit

@Model
final class ArticleState {

    // MARK: - Persisted Properties

    /// SHA-256 hash of `articleURL` (hex string).
    /// Used as the stable cross-device key — UUIDs differ per device.
    @Attribute(.unique) var articleURLHash: String

    /// The original article URL. Stored for debugging and de-duplication.
    var articleURL: String

    /// Monotonic: once true on any device, never reverted by sync.
    var isRead: Bool = false

    /// Timestamp-based conflict resolution — most recent write wins.
    var isBookmarked: Bool = false

    /// Manually flagged as paywalled by the user.
    var isPaywalled: Bool = false

    /// Updated on every write. Used to resolve bookmark conflicts.
    var lastModifiedAt: Date

    // MARK: - Initialization

    init(articleURL: String) {
        self.articleURL = articleURL
        self.articleURLHash = ArticleState.hash(articleURL)
        self.lastModifiedAt = Date()
    }

    // MARK: - Hash Helper

    static func hash(_ url: String) -> String {
        let data = Data(url.utf8)
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
```

---

## Part 2: UserPreferences.swift

Create at `OpenRSS/Models/UserPreferences.swift`.

```swift
//
//  UserPreferences.swift
//  OpenRSS
//
//  SwiftData model for synced user settings.
//  Singleton record — only one instance exists, keyed by id = "singleton".
//

import Foundation
import SwiftData

@Model
final class UserPreferences {

    // MARK: - Persisted Properties

    /// Singleton key. Always "singleton". @Attribute(.unique) enforces one record.
    @Attribute(.unique) var id: String = "singleton"

    /// Raw value of RefreshInterval enum (e.g. "30 Minutes").
    var refreshIntervalRaw: String = RefreshInterval.thirtyMinutes.rawValue

    /// "System", "Light", or "Dark".
    var theme: String = "System"

    var showImages: Bool = true
    var openLinksInApp: Bool = true
    var markAsReadOnScroll: Bool = false
    var cacheEnabled: Bool = true

    /// "Small", "Medium", "Large".
    var textSize: String = "Medium"

    // MARK: - Computed

    var refreshInterval: RefreshInterval {
        get { RefreshInterval(rawValue: refreshIntervalRaw) ?? .thirtyMinutes }
        set { refreshIntervalRaw = newValue.rawValue }
    }

    // MARK: - Initialization

    init() {}
}
```

---

## Part 3: SyncService.swift

Create at `OpenRSS/Services/SyncService.swift`.

```swift
//
//  SyncService.swift
//  OpenRSS
//
//  Monitors NSPersistentCloudKitContainer events and exposes sync state to the UI.
//  Also handles post-sync feed deduplication and cascade delete cleanup.
//

import Foundation
import CoreData
import SwiftData
import Observation

// MARK: - SyncState

enum SyncState: Equatable {
    case synced
    case syncing
    case waiting          // Queued but no network
    case error(String)    // Error message for display
    case disabled         // Guest mode — no CloudKit

    var icon: String {
        switch self {
        case .synced:    return "checkmark.icloud"
        case .syncing:   return "arrow.triangle.2.circlepath"
        case .waiting:   return "clock.fill"
        case .error:     return "exclamationmark.icloud"
        case .disabled:  return "xmark.icloud"
        }
    }

    var label: String {
        switch self {
        case .synced:         return "Up to date"
        case .syncing:        return "Syncing…"
        case .waiting:        return "Waiting for network"
        case .error(let msg): return "Error: \(msg)"
        case .disabled:       return "Sign in to sync"
        }
    }

    static func == (lhs: SyncState, rhs: SyncState) -> Bool {
        switch (lhs, rhs) {
        case (.synced, .synced),
             (.syncing, .syncing),
             (.waiting, .waiting),
             (.disabled, .disabled):
            return true
        case (.error(let a), .error(let b)):
            return a == b
        default:
            return false
        }
    }
}

// MARK: - SyncService

@Observable
final class SyncService {

    // MARK: - Singleton

    static let shared = SyncService()
    private init() {}

    // MARK: - Observable State

    private(set) var syncState: SyncState = .disabled
    private(set) var lastSyncDate: Date?

    // MARK: - Internal

    private var observer: NSObjectProtocol?

    // MARK: - Start Monitoring

    /// Call this after the ModelContainer is created (in OpenRSSApp.init or body).
    /// Pass `isCloudKitEnabled: false` for guest mode — shows disabled state immediately.
    func startMonitoring(isCloudKitEnabled: Bool) {
        guard isCloudKitEnabled else {
            syncState = .disabled
            return
        }

        syncState = .syncing

        // Observe NSPersistentCloudKitContainer events bridged through NotificationCenter.
        // SwiftData uses NSPersistentCloudKitContainer under the hood.
        let notificationName = NSNotification.Name("NSPersistentCloudKitContainerEventChangedNotification")

        observer = NotificationCenter.default.addObserver(
            forName: notificationName,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            self?.handleSyncEvent(notification)
        }
    }

    func stopMonitoring() {
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
    }

    // MARK: - Event Handling

    private func handleSyncEvent(_ notification: Notification) {
        // NSPersistentCloudKitContainerEvent is bridged via userInfo
        guard let event = notification.userInfo?["event"] else { return }

        // Use Mirror to read properties without importing CoreData internals
        let mirror = Mirror(reflecting: event)
        let props = Dictionary(
            mirror.children.compactMap { child -> (String, Any)? in
                guard let label = child.label else { return nil }
                return (label, child.value)
            },
            uniquingKeysWith: { first, _ in first }
        )

        let succeeded = props["succeeded"] as? Bool ?? true
        let typeRaw   = props["type"] as? Int ?? 0

        if !succeeded {
            let errorDesc = (props["error"] as? Error)?.localizedDescription ?? "Unknown error"
            syncState = .error(errorDesc)
            return
        }

        // Type: 0 = setup, 1 = import, 2 = export
        switch typeRaw {
        case 0:  // setup
            syncState = .syncing
        case 1:  // import (data arriving from cloud)
            syncState = .syncing
            handlePostImport()
        case 2:  // export (local changes pushed)
            syncState = .synced
            lastSyncDate = Date()
            updateUserProfileSyncDate()
        default:
            syncState = .synced
        }
    }

    // MARK: - Post-Import Deduplication

    /// After a CloudKit import, check for duplicate feeds (same feedURL, different UUIDs).
    /// Keeps the oldest record, re-assigns folder relationships, deletes duplicates.
    private func handlePostImport() {
        Task { @MainActor in
            let service = SwiftDataService.shared
            let allSources = service.sources

            // Group by feedURL (lowercased for case-insensitive dedup)
            var urlGroups: [String: [Source]] = [:]
            for source in allSources {
                let key = source.feedURL.lowercased()
                urlGroups[key, default: []].append(source)
            }

            // Find duplicates — groups with more than 1 entry
            for (_, group) in urlGroups where group.count > 1 {
                // Keep the oldest (earliest addedAt)
                let sorted = group.sorted { $0.addedAt < $1.addedAt }
                let duplicates = Array(sorted.dropFirst())
                for dup in duplicates {
                    try? service.deleteFeed(id: dup.id)
                }
            }

            syncState = .synced
            lastSyncDate = Date()
        }
    }

    // MARK: - Helpers

    private func updateUserProfileSyncDate() {
        Task { @MainActor in
            SwiftDataService.shared.updateProfileSyncDate()
        }
    }
}
```

---

## Part 4: Update OpenRSSApp.swift

The `ModelContainer` setup must choose between CloudKit-backed and local-only based on whether a user is signed in. The trick: check the Keychain directly in `init()` — before `AuthenticationManager` is configured — because Keychain doesn't need a container.

### 4a — Add `import CryptoKit` at the top

```swift
import CryptoKit
```

### 4b — Expand the schema

Find the `Schema([...])` call and add the two new models:

```swift
let schema = Schema([
    FolderModel.self,
    FeedModel.self,
    CachedArticle.self,
    UserProfile.self,
    ArticleState.self,       // ← add
    UserPreferences.self,    // ← add
])
```

### 4c — Conditional ModelConfiguration

Replace:

```swift
let config = ModelConfiguration(schema: schema)
```

With:

```swift
// Check Keychain directly — AuthenticationManager isn't configured yet.
// If an Apple user ID is stored, the user was previously signed in.
let isSignedIn = KeychainService.loadAppleUserID() != nil

let config = ModelConfiguration(
    schema: schema,
    cloudKitDatabase: isSignedIn ? .automatic : .none
)
```

### 4d — Start SyncService after bootstrap

Inside the `MainActor.assumeIsolated { ... }` block, after the existing bootstrap calls, add:

```swift
SyncService.shared.startMonitoring(isCloudKitEnabled: isSignedIn)
```

### 4e — Restart SyncService after sign-in / sign-out

Sign-in and sign-out require a container swap (local → CloudKit and vice versa). The cleanest approach for now is to restart the app state. Add this notification handler in the `body` scene:

```swift
.onReceive(
    NotificationCenter.default.publisher(
        for: Notification.Name("OpenRSS.AuthStateChanged")
    )
) { _ in
    // The user just signed in or out — the next launch will pick up
    // the correct ModelContainer. For the current session, SyncService
    // reflects the new state immediately.
    let isNowSignedIn = AuthenticationManager.shared.isSignedIn
    SyncService.shared.startMonitoring(isCloudKitEnabled: isNowSignedIn)
}
```

Then fire this notification from `AuthenticationManager` at the end of `signIn(with:)` and `signOut()`:

```swift
NotificationCenter.default.post(name: Notification.Name("OpenRSS.AuthStateChanged"), object: nil)
```

> **Full container swap note:** A true zero-restart container swap (local SwiftData → CloudKit SwiftData) requires `SwiftDataService.configure(container:)` to be called again with a new container. This is a Phase 4 task (Migration). For now, the app syncs after the next launch following sign-in. Document this behavior clearly in the UI ("Sync starts after relaunch").

---

## Part 5: Update SwiftDataService.swift

Article read/bookmark state currently only lives in the in-memory `articles` array. It must now also write to `ArticleState` so CloudKit can sync it.

### 5a — Add `import CryptoKit` at the top

### 5b — Replace `markAsRead(_:)`

```swift
func markAsRead(_ articleID: UUID) {
    if let i = articles.firstIndex(where: { $0.id == articleID }) {
        articles[i].isRead = true
        upsertArticleState(articleURL: articles[i].articleURL, isRead: true)
    }
}
```

### 5c — Replace `markAsUnread(_:)`

```swift
func markAsUnread(_ articleID: UUID) {
    if let i = articles.firstIndex(where: { $0.id == articleID }) {
        articles[i].isRead = false
        // Note: isRead in ArticleState is monotonic for sync purposes.
        // We update the in-memory state but do NOT flip ArticleState.isRead to false.
        // This prevents a locally un-read article from un-reading it on another device.
    }
}
```

### 5d — Replace `toggleBookmark(for:)`

```swift
func toggleBookmark(for articleID: UUID) {
    if let i = articles.firstIndex(where: { $0.id == articleID }) {
        articles[i].isBookmarked.toggle()
        upsertArticleState(
            articleURL: articles[i].articleURL,
            isBookmarked: articles[i].isBookmarked
        )
    }
}
```

### 5e — Replace `markArticlePaywalled(id:)`

```swift
@MainActor
func markArticlePaywalled(id: UUID) {
    guard let index = articles.firstIndex(where: { $0.id == id }) else { return }
    articles[index].isPaywalled = true
    upsertArticleState(articleURL: articles[index].articleURL, isPaywalled: true)
}
```

### 5f — Update `syncArticles(_:)` to hydrate state from ArticleState

Replace the existing `syncArticles` method:

```swift
@MainActor
func syncArticles(_ pipelineArticles: [Article]) {
    guard !pipelineArticles.isEmpty else { return }

    // Preserve read/bookmark state — check in-memory first, then ArticleState
    let existingInMemory = Dictionary(
        articles.map { ($0.articleURL, (isRead: $0.isRead, isBookmarked: $0.isBookmarked)) },
        uniquingKeysWith: { first, _ in first }
    )

    let merged = pipelineArticles.map { article -> Article in
        var updated = article

        if let mem = existingInMemory[article.articleURL] {
            // In-memory state takes precedence (most recent)
            updated.isRead = mem.isRead
            updated.isBookmarked = mem.isBookmarked
        } else {
            // Fall back to ArticleState (synced from another device)
            if let state = fetchArticleState(for: article.articleURL) {
                updated.isRead = state.isRead
                updated.isBookmarked = state.isBookmarked
                updated.isPaywalled = state.isPaywalled
            }
        }

        return updated
    }.sorted { $0.publishedAt > $1.publishedAt }

    self.articles = merged
    ArticleCacheStore.save(merged)
}
```

### 5g — Add the new private ArticleState methods

Add these private methods inside `SwiftDataService`, below the existing private helpers:

```swift
// MARK: - ArticleState Persistence

/// Upserts an ArticleState record for the given article URL.
/// Pass only the flags you want to update; nil values are left unchanged.
@MainActor
private func upsertArticleState(
    articleURL: String,
    isRead: Bool? = nil,
    isBookmarked: Bool? = nil,
    isPaywalled: Bool? = nil
) {
    guard let context = modelContext else { return }
    let hash = ArticleState.hash(articleURL)

    let descriptor = FetchDescriptor<ArticleState>(
        predicate: #Predicate { $0.articleURLHash == hash }
    )

    let state: ArticleState
    if let existing = try? context.fetch(descriptor).first {
        state = existing
    } else {
        state = ArticleState(articleURL: articleURL)
        context.insert(state)
    }

    // isRead is monotonic — only ever set to true, never back to false
    if let isRead, isRead == true { state.isRead = true }
    if let isBookmarked { state.isBookmarked = isBookmarked }
    if let isPaywalled { state.isPaywalled = isPaywalled }
    state.lastModifiedAt = Date()

    try? context.save()
}

/// Fetches the ArticleState for a given article URL, or nil if not found.
@MainActor
private func fetchArticleState(for articleURL: String) -> ArticleState? {
    guard let context = modelContext else { return nil }
    let hash = ArticleState.hash(articleURL)
    let descriptor = FetchDescriptor<ArticleState>(
        predicate: #Predicate { $0.articleURLHash == hash }
    )
    return try? context.fetch(descriptor).first
}

// MARK: - UserPreferences

/// Returns the singleton UserPreferences record, creating it if needed.
@MainActor
func userPreferences() -> UserPreferences {
    guard let context = modelContext else { return UserPreferences() }
    let descriptor = FetchDescriptor<UserPreferences>()
    if let existing = try? context.fetch(descriptor).first {
        return existing
    }
    let prefs = UserPreferences()
    context.insert(prefs)
    try? context.save()
    return prefs
}

/// Updates UserProfile.lastSyncedAt after a successful CloudKit export.
@MainActor
func updateProfileSyncDate() {
    guard let context = modelContext else { return }
    let descriptor = FetchDescriptor<UserProfile>()
    if let profile = try? context.fetch(descriptor).first {
        profile.lastSyncedAt = Date()
        try? context.save()
    }
}
```

---

## Part 6: Update SettingsView.swift

Settings must now read from and write to `UserPreferences` so they sync across devices. The existing `RefreshStateStore` binding stays for scheduling, but the source of truth for the displayed value moves to `UserPreferences`.

### 6a — Add `userPrefs` alongside `refreshStore`

```swift
// Existing
private var refreshStore = RefreshStateStore.shared

// Add
@State private var userPrefs: UserPreferences? = nil
```

### 6b — Load `userPrefs` on appear

In both `liquidGlassBody` and `legacyBody`, add `.onAppear`:

```swift
.onAppear {
    userPrefs = SwiftDataService.shared.userPreferences()
}
```

### 6c — Wire the interval picker to both stores

Replace the existing interval picker call:

```swift
settingsPicker(title: "Refresh Interval", selection: Binding(
    get: { refreshStore.refreshInterval },
    set: {
        refreshStore.refreshInterval = $0
        userPrefs?.refreshInterval = $0
    }
))
```

### 6d — Wire the toggles to UserPreferences

Replace the existing `settingsToggle` calls in `appearanceSection` and `readingSection`:

```swift
// Show Article Images
settingsToggle(title: "Show Article Images", isOn: Binding(
    get: { userPrefs?.showImages ?? true },
    set: { userPrefs?.showImages = $0 }
))

// Open Links in App
settingsToggle(title: "Open Links in App", isOn: Binding(
    get: { userPrefs?.openLinksInApp ?? true },
    set: { userPrefs?.openLinksInApp = $0 }
))

// Mark as Read on Scroll
settingsToggle(title: "Mark as Read on Scroll", isOn: Binding(
    get: { userPrefs?.markAsReadOnScroll ?? false },
    set: { userPrefs?.markAsReadOnScroll = $0 }
))

// Cache Articles
settingsToggle(title: "Cache Articles", isOn: Binding(
    get: { userPrefs?.cacheEnabled ?? true },
    set: { userPrefs?.cacheEnabled = $0 }
))
```

---

## Part 7: Update AccountView.swift

The `AccountView` currently has placeholder "Coming soon" sync status. Replace it with live `SyncService` data.

### 7a — Add `syncService` reference

```swift
private var syncService: SyncService { .shared }
```

### 7b — Replace `syncSection`

Replace the entire `syncSection` computed property:

```swift
private var syncSection: some View {
    settingsSection(title: "iCloud Sync", icon: "icloud.fill") {
        VStack(spacing: 0) {
            // Sync status row
            HStack {
                Image(systemName: syncService.syncState.icon)
                    .font(.system(size: 16))
                    .foregroundStyle(syncStateColor)

                Text(syncService.syncState.label)
                    .font(.system(size: 16))
                    .foregroundStyle(Design.Colors.primaryText(for: colorScheme))

                Spacer()

                if syncService.syncState == .syncing {
                    ProgressView()
                        .scaleEffect(0.8)
                }
            }
            .padding(.horizontal, Design.Spacing.edge)
            .padding(.vertical, 14)

            divider

            // Last synced row
            HStack {
                Text("Last Synced")
                    .font(.system(size: 16))
                    .foregroundStyle(Design.Colors.primaryText(for: colorScheme))

                Spacer()

                if let date = syncService.lastSyncDate {
                    Text(date, style: .relative)
                        .font(.system(size: 14))
                        .foregroundStyle(Design.Colors.secondaryText(for: colorScheme))
                } else {
                    Text("Never")
                        .font(.system(size: 14))
                        .foregroundStyle(Design.Colors.secondaryText(for: colorScheme))
                }
            }
            .padding(.horizontal, Design.Spacing.edge)
            .padding(.vertical, 14)
        }
    }
}

private var syncStateColor: Color {
    switch syncService.syncState {
    case .synced:   return .green
    case .syncing:  return Design.Colors.primary
    case .waiting:  return .gray
    case .error:    return .red
    case .disabled: return .gray
    }
}
```

---

## Part 8: Xcode Capabilities (Manual Steps)

These cannot be done in code and must be done in Xcode:

### 8a — iCloud Capability

1. Open `OpenRSS.xcodeproj`
2. Select the `OpenRSS` target → **Signing & Capabilities**
3. Click **+ Capability** → add **iCloud**
4. Under iCloud, check **CloudKit**
5. Under CloudKit, ensure a container is selected (Xcode creates one automatically: `iCloud.DariusEhsani.OpenRSS`)

### 8b — Background Modes (if not already present)

Under **Signing & Capabilities**, confirm **Background Modes** is present and **Background fetch** is checked. This was added in the Background Refresh guide — verify it survived the auth branch merge.

---

## Testing Checklist

### Simulator + iPhone Setup
- Sign the same Apple ID into both Simulator (Settings → Apple ID) and your iPhone
- Both must use the same iCloud account — this is the only requirement for sync to work
- Use **CloudKit Dashboard** (iCloud.developer.apple.com) to inspect records directly

### Sync Tests

**Feeds and folders:**
- [ ] Add a folder on Simulator → appears on iPhone within ~15 seconds
- [ ] Delete a folder on iPhone → removed on Simulator
- [ ] Add a feed to a folder on iPhone → folder + feed appear on Simulator

**Article state:**
- [ ] Mark article as read on Simulator → shows as read on iPhone after sync
- [ ] Bookmark an article on iPhone → bookmark appears on Simulator
- [ ] Mark as read on Device A while offline → goes online → Device B shows it as read

**Conflict resolution:**
- [ ] Both devices offline, mark same article read on both → both show read (monotonic)
- [ ] Both devices offline, bookmark on Device A, un-bookmark on Device B → Device A's action wins if more recent (`lastModifiedAt`)

**UserPreferences sync:**
- [ ] Change refresh interval to "Daily" on Simulator → opens iPhone → interval is "Daily"
- [ ] Toggle "Show Images" off on iPhone → Simulator reflects the change

**Sync status UI:**
- [ ] Open AccountView during active sync → spinner visible, state shows "Syncing…"
- [ ] After sync completes → "Up to date" with checkmark, "Last Synced" shows relative time
- [ ] Turn on airplane mode → state transitions to "Waiting for network"

**Guest mode:**
- [ ] App in guest mode → AccountView shows "Sign in to sync" (disabled state)
- [ ] No CloudKit errors in console for guest mode

**Error state:**
- [ ] Sign out of iCloud on device mid-session → error state appears in AccountView

---

## Conflict Resolution Summary

| Data | Rule | Implementation |
|---|---|---|
| `FolderModel` name/icon | Last-writer-wins | CloudKit default — no custom code |
| `FeedModel` enabled/paywalled | Last-writer-wins | CloudKit default — no custom code |
| `ArticleState.isRead` | Monotonic (OR) | `upsertArticleState` only writes `true`, never `false` |
| `ArticleState.isBookmarked` | Latest `lastModifiedAt` wins | CloudKit default with timestamp — correct behavior |
| `UserPreferences` | Last-writer-wins | CloudKit default — settings changes are infrequent |
| Duplicate feeds (same feedURL) | Keep oldest, delete newer | `SyncService.handlePostImport()` deduplication |

---

## Notes for the Agent

- `CryptoKit` must be imported in both `ArticleState.swift` and `SwiftDataService.swift` for `SHA256.hash(data:)`.
- The `ModelConfiguration(cloudKitDatabase: .automatic)` call requires the **iCloud capability with CloudKit enabled** in Xcode. Without it, the container creation will fail silently and fall back to local storage.
- `cloudKitDatabase: .automatic` uses the app's default CloudKit container (`iCloud.<bundle-id>`). Do not pass a custom container string — let it auto-detect.
- `ArticleState` records will accumulate indefinitely. Add a purge in the existing `purgeOldArticleCache(olderThan:)` method to also delete `ArticleState` records for articles older than 90 days.
- The `NSPersistentCloudKitContainerEventChangedNotification` name is not a public constant in SwiftData's Swift API — use the string literal as shown in `SyncService`. This is a known gap in SwiftData's CloudKit bridging as of iOS 17/18.
- Do **not** mark `CachedArticle` with `.cloudKitDatabase: .automatic` if extracted content is large. The design doc recommends skipping sync for `CachedArticle` records > 2 MB. For now, the safest option is to exclude `CachedArticle` from the CloudKit-enabled schema by using a separate `ModelConfiguration` — one with CloudKit for the main models, one without for `CachedArticle`. This requires two configurations in the same `ModelContainer` (SwiftData supports this via the `configurations:` array).
- `isRead` monotonicity is enforced at the app level in `upsertArticleState`. CloudKit itself will still sync the field — the monotonic guarantee only holds if all devices run this app version. Older app versions that wrote `isRead = false` could create a conflict. This is acceptable for the current scope.
- The `UserPreferences` singleton is keyed by `id = "singleton"`. If the CloudKit import creates a second record (unlikely but possible during first sync), `userPreferences()` will return the first one found. Add a cleanup pass in `handlePostImport()` if this becomes an issue in testing.
