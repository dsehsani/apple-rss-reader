# OpenRSS — Accounts & iCloud Sync

**Architecture Design Document**
April 2026 | v1.0

---

## 1. Executive Summary

This document defines the architecture for adding user accounts and cross-device sync to OpenRSS. The design introduces Sign in with Apple for identity, CloudKit for transparent data synchronization, and a migration path from the existing local-only SwiftData store to a cloud-backed architecture.

The system will sync all user data across devices: feed subscriptions, folder organization, article read and bookmark state, user preferences, and extracted article cache. Conflict resolution uses a last-writer-wins strategy with vector clocks for critical state like read/bookmark status.

> **Design Principles:** Offline-first — the app works fully without network. Sync is eventual, transparent, and non-blocking. No user data leaves the Apple ecosystem. The existing `FeedDataService` protocol boundary ensures ViewModels require zero changes.

---

## 2. Current Architecture

Understanding the current architecture is critical for planning a non-breaking migration. OpenRSS currently uses a clean layered architecture with a protocol boundary between ViewModels and data storage.

### 2.1 Data Models

| Model | Storage | Description |
|-------|---------|-------------|
| `FolderModel` | SwiftData `@Model` | User-created folders with name, icon, color, sort order. Cascade-deletes feeds. |
| `FeedModel` | SwiftData `@Model` | RSS subscriptions with URL, title, enabled/paywalled flags. Belongs to a folder. |
| `Article` | JSON file cache | In-memory domain model (`Codable`). 7-day rolling cache in Caches directory. |
| `CachedArticle` | SwiftData `@Model` | Extracted article content (serialized `ContentNode` tree). L2 disk cache. |
| `Source` / `Category` | In-memory only | Domain models mapped from `FeedModel`/`FolderModel`. Not persisted directly. |

### 2.2 Service Layer

`SwiftDataService` is a singleton `@Observable` class implementing the `FeedDataService` protocol. It owns the `ModelContext`, exposes `categories`/`sources`/`articles` arrays, and handles all CRUD operations. ViewModels only interact through the protocol, meaning they are decoupled from the storage mechanism. This is the key seam for introducing CloudKit.

Articles are currently loaded from a JSON cache (`ArticleCacheStore`) on launch and refreshed from RSS feeds via `RSSService`. Read/bookmark state lives only in the in-memory `Article` array and the JSON cache, which is not synced.

---

## 3. Authentication Architecture

### 3.1 Sign in with Apple

Sign in with Apple is the primary (and initially only) authentication method. It provides a privacy-preserving identity without requiring email/password infrastructure or a custom auth backend.

| Component | Technology | Purpose |
|-----------|-----------|---------|
| Identity Provider | `AuthenticationServices` framework | Sign in with Apple button and credential flow |
| User Record | New `UserProfile` SwiftData model | Stores Apple user ID, display name, email relay, preferences |
| Session State | `AuthenticationManager` (`@Observable`) | Tracks signed-in state, current user, token refresh |
| Keychain | `Security` framework | Persists Apple user identifier across app installs |

### 3.2 Auth Flow

**First Launch:** The app presents an onboarding screen with a Sign in with Apple button. On success, the app receives a user identifier, optional full name, and an email relay address. These are stored in a new `UserProfile` SwiftData model and the identifier is persisted to Keychain for silent re-authentication.

**Subsequent Launches:** The app calls `ASAuthorizationAppleIDProvider.getCredentialState(forUserID:)` to verify the user is still authorized. If the credential is revoked, the app shows a re-auth screen. If valid, the session is silently restored from Keychain.

**Guest Mode:** Users can skip sign-in and use the app locally. All data stays in the local SwiftData store. When they later sign in, a one-time migration merges local data into the CloudKit-backed store.

### 3.3 New Models

```swift
@Model final class UserProfile {
    @Attribute(.unique) var appleUserID: String
    var displayName: String?
    var emailRelay: String?
    var avatarData: Data?
    var createdAt: Date
    var lastSyncedAt: Date?
    var syncEnabled: Bool = true
}
```

### 3.4 AuthenticationManager

A new `@Observable` singleton that owns the auth lifecycle and exposes a simple API for the rest of the app:

```swift
@Observable final class AuthenticationManager {
    static let shared = AuthenticationManager()

    enum AuthState { case unknown, signedOut, signedIn(UserProfile) }

    private(set) var state: AuthState = .unknown
    var isSignedIn: Bool { if case .signedIn = state { true } else { false } }
    var currentUser: UserProfile? { if case .signedIn(let u) = state { u } else { nil } }

    func signInWithApple() async throws { /* ASAuthorization flow */ }
    func checkExistingCredential() async { /* getCredentialState */ }
    func signOut() { /* Clear Keychain, reset state */ }
}
```

---

## 4. iCloud Sync Architecture

### 4.1 Approach: SwiftData + CloudKit

SwiftData supports CloudKit integration natively by setting `cloudKitDatabase: .automatic` on the `ModelConfiguration`. This uses the `CKContainer.default()` private database, meaning all user data stays within their iCloud account. No custom CloudKit record types or subscriptions are needed — SwiftData handles the mapping.

> **Why SwiftData + CloudKit (not raw CKRecord):** Your existing models are already SwiftData `@Model` classes. The SwiftData-CloudKit integration automatically mirrors local changes to the cloud with zero additional code for basic CRUD. This avoids building a custom sync engine, CKRecord serialization, and subscription management. The tradeoff is less granular control, but for OpenRSS's data profile (low write volume, small payloads) this is the correct choice.

### 4.2 Data Sync Scope

| Data | Sync Method | Notes |
|------|-------------|-------|
| `FolderModel` | SwiftData CloudKit (automatic) | Name, icon, color, sort order. Relationship to feeds. |
| `FeedModel` | SwiftData CloudKit (automatic) | URL, title, enabled/paywalled flags. Folder relationship. |
| `ArticleState` (new) | SwiftData CloudKit (automatic) | Read, bookmarked, paywalled flags keyed by article URL hash. |
| `UserPreferences` (new) | SwiftData CloudKit (automatic) | Refresh interval, theme, text size, open-in-app toggle. |
| `CachedArticle` | SwiftData CloudKit (selective) | Only cached if < 2 MB. Large extractions stay local-only. |
| `Article` (feed items) | NOT synced | Re-fetched from RSS on each device. Only state is synced. |

### 4.3 New Sync Models

Two new SwiftData models are needed to sync state that currently only lives in memory:

```swift
@Model final class ArticleState {
    /// SHA-256 hash of the article URL, used as a stable cross-device key.
    @Attribute(.unique) var articleURLHash: String
    var articleURL: String
    var isRead: Bool = false
    var isBookmarked: Bool = false
    var isPaywalled: Bool = false
    var lastModifiedAt: Date  // Vector clock for conflict resolution
}
```

```swift
@Model final class UserPreferences {
    @Attribute(.unique) var id: String = "singleton"
    var refreshInterval: String = "Hourly"
    var theme: String = "System"
    var showImages: Bool = true
    var openLinksInApp: Bool = true
    var markAsReadOnScroll: Bool = false
    var textSize: String = "Medium"
    var cacheEnabled: Bool = true
}
```

### 4.4 ModelContainer Configuration

The app entry point changes to configure CloudKit when a user is signed in:

```swift
let schema = Schema([
    FolderModel.self, FeedModel.self, CachedArticle.self,
    UserProfile.self, ArticleState.self, UserPreferences.self
])

let config: ModelConfiguration
if AuthenticationManager.shared.isSignedIn {
    config = ModelConfiguration(
        schema: schema,
        cloudKitDatabase: .automatic  // Enables iCloud sync
    )
} else {
    config = ModelConfiguration(
        schema: schema,
        cloudKitDatabase: .none  // Local-only for guest mode
    )
}
container = try ModelContainer(for: schema, configurations: config)
```

---

## 5. Conflict Resolution

When the same data is modified on two devices while offline, conflicts arise on the next sync. SwiftData + CloudKit uses a last-writer-wins strategy by default, but OpenRSS needs smarter handling for certain data types.

### 5.1 Strategy by Data Type

| Data Type | Strategy | Rationale |
|-----------|----------|-----------|
| `FolderModel` | Last-writer-wins (default) | Low conflict probability. User rarely edits folder names simultaneously. |
| `FeedModel` | Last-writer-wins (default) | Same reasoning. Adding the same feed on two devices deduplicates by URL. |
| `ArticleState.isRead` | Logical OR (custom) | Once read on any device, it should be read everywhere. Never un-read by sync. |
| `ArticleState.isBookmarked` | Timestamp-based (`lastModifiedAt`) | Most recent intentional action wins. |
| `UserPreferences` | Last-writer-wins (default) | Settings changes are infrequent and intentional. |
| `CachedArticle` | Skip on conflict | Re-extraction is cheap. Never overwrite a local cache. |

### 5.2 Custom Merge for ArticleState

The `ArticleState` model uses a custom merge policy in the `NSPersistentCloudKitContainer` history processing. The key rule: `isRead` is a monotonic flag (once true, always true), while `isBookmarked` uses the `lastModifiedAt` timestamp to determine the winner.

```swift
extension SwiftDataService {
    func mergeArticleState(local: ArticleState, remote: ArticleState) -> ArticleState {
        // Read is monotonic: once read, always read
        local.isRead = local.isRead || remote.isRead

        // Bookmark uses latest timestamp
        if remote.lastModifiedAt > local.lastModifiedAt {
            local.isBookmarked = remote.isBookmarked
            local.lastModifiedAt = remote.lastModifiedAt
        }
        return local
    }
}
```

### 5.3 Feed Deduplication

If a user adds the same RSS feed on two devices before sync completes, both devices will push a `FeedModel` with the same `feedURL` but different UUIDs. The sync layer detects this by running a uniqueness check on `feedURL` after each CloudKit import and merges the duplicates, keeping the older record and reassigning any folder relationships.

---

## 6. Migration Strategy

Existing users have local data that must be preserved when they sign in and enable sync for the first time. This is a one-time migration that runs after the first successful Sign in with Apple.

### 6.1 Migration Steps

1. User signs in with Apple for the first time.
2. App creates a new `ModelContainer` with `cloudKitDatabase: .automatic`.
3. `MigrationService` reads all records from the old local-only store.
4. Records are inserted into the new CloudKit-backed store, preserving UUIDs.
5. Article read/bookmark state from the JSON cache is converted to `ArticleState` records.
6. Settings are written to a `UserPreferences` record.
7. Old local store file is archived (not deleted) for 30 days as a safety net.
8. `SwiftDataService` switches its `ModelContext` to the new container.

> **Rollback Safety:** The old store is archived rather than deleted. If the user signs out or encounters sync issues within 30 days, the app can restore from the archive. After 30 days, a background task removes the archive.

---

## 7. Required Architecture Changes

### 7.1 New Files

| File | Layer | Purpose |
|------|-------|---------|
| `AuthenticationManager.swift` | Services | `@Observable` singleton managing Sign in with Apple lifecycle |
| `UserProfile.swift` | Models | SwiftData model for Apple ID identity and sync metadata |
| `ArticleState.swift` | Models | SwiftData model for synced read/bookmark/paywall state |
| `UserPreferences.swift` | Models | SwiftData model for synced app settings |
| `SyncService.swift` | Services | Monitors CloudKit sync status, handles merge conflicts |
| `MigrationService.swift` | Services | One-time local-to-cloud data migration |
| `OnboardingView.swift` | Views | Sign in with Apple screen with guest mode option |
| `AccountView.swift` | Views | Account management (profile, sync status, sign out) |
| `SyncStatusView.swift` | Views/Components | Sync indicator (checkmark, spinner, error badge) |

### 7.2 Modified Files

| File | Changes |
|------|---------|
| `OpenRSSApp.swift` | Conditional `ModelContainer` setup (CloudKit vs local). Auth state check on launch. Schema expanded. |
| `SwiftDataService.swift` | Article state reads/writes go through `ArticleState` model. New `configure(container:authManager:)` method. |
| `SettingsView.swift` | New Account section at top. Sync toggle. Settings bound to `UserPreferences` model. |
| `MainTabView.swift` | Conditionally show `OnboardingView` if not signed in (or guest mode acknowledged). |
| `TodayViewModel.swift` | Read/bookmark state lookups merge in-memory `Article` with persisted `ArticleState`. |
| `ArticleCacheStore.swift` | Saves `ArticleState` records alongside JSON cache. Hydrates state on load. |

### 7.3 SwiftDataService Changes

The most significant change is to `SwiftDataService`, which must now reconcile the in-memory `Article` array with persisted `ArticleState` records. The key methods that change:

```swift
// markAsRead now persists to ArticleState for sync
func markAsRead(_ articleID: UUID) {
    if let i = articles.firstIndex(where: { $0.id == articleID }) {
        articles[i].isRead = true
        upsertArticleState(for: articles[i], isRead: true)
    }
}

// New method: upsert ArticleState for sync
private func upsertArticleState(
    for article: Article,
    isRead: Bool? = nil,
    isBookmarked: Bool? = nil
) {
    let hash = SHA256.hash(article.articleURL)
    let state = fetchOrCreateArticleState(hash: hash, url: article.articleURL)
    if let isRead { state.isRead = isRead }
    if let isBookmarked { state.isBookmarked = isBookmarked }
    state.lastModifiedAt = Date()
    try? modelContext?.save()
}
```

---

## 8. Sync Status UI

Users need visibility into sync state without it being intrusive. The design adds a subtle sync indicator to the Settings tab and a detailed sync status view accessible from the Account section.

### 8.1 Sync States

| State | Icon | Description |
|-------|------|-------------|
| Synced | `checkmark.icloud` (green) | All local changes have been pushed to iCloud. |
| Syncing | `arrow.triangle.2.circlepath` (blue, animated) | Active upload or download in progress. |
| Waiting | `clock.fill` (gray) | Changes queued, waiting for network connectivity. |
| Error | `exclamationmark.icloud` (red) | Sync failed. Tappable for details and retry. |
| Disabled | `xmark.icloud` (gray) | User has turned off sync in Settings. |

### 8.2 SyncService

A new `@Observable` service that monitors `NSPersistentCloudKitContainer` events and exposes sync status to the UI:

```swift
@Observable final class SyncService {
    static let shared = SyncService()

    enum SyncState { case synced, syncing, waiting, error(Error), disabled }

    private(set) var state: SyncState = .synced
    private(set) var lastSyncDate: Date?
    private(set) var pendingChangeCount: Int = 0

    func startMonitoring(container: ModelContainer) {
        // Observe NSPersistentCloudKitContainer.eventChangedNotification
        // Update state based on event type: setup, import, export
    }

    func forceSync() async { /* Trigger NSPersistentCloudKitContainer export */ }
}
```

---

## 9. CloudKit Constraints & Mitigations

CloudKit has limitations that affect design decisions:

| Constraint | Impact | Mitigation |
|------------|--------|------------|
| No unique constraints on `CKRecord` | `FeedModel.feedURL` can't be enforced unique in CloudKit | App-level deduplication after each CloudKit import event |
| 5 MB per `CKRecord` asset | Large `CachedArticle.serializedNodes` may exceed limit | Skip CloudKit sync for `CachedArticle` records > 2 MB |
| No cascade delete in CloudKit | SwiftData cascade delete is local-only | `SyncService` processes deletions and removes orphaned feeds |
| Slow initial sync (~10–60s) | New device shows empty state during first sync | Show progress indicator; pre-populate from JSON cache meanwhile |
| No real-time push (polling) | Changes from another device have ~15s delay | Acceptable for RSS reader. Manual pull-to-refresh triggers sync. |
| Rate limits (40 req/s) | Bulk migration could hit limits | Batch migration inserts with 100ms throttle between batches |

---

## 10. Security & Privacy

- All user data is stored in the CloudKit private database, visible only to the authenticated Apple ID.
- Apple's email relay is used when the user opts to hide their email during Sign in with Apple.
- The Apple user identifier is stored in Keychain (not UserDefaults) to survive app reinstalls securely.
- No user data is sent to any third-party server. RSS feed URLs are fetched directly from publishers.
- The app uses Apple's end-to-end encrypted iCloud infrastructure. OpenRSS has no server-side access to user data.
- Guest mode users have no data leave the device. Signing in is always optional.

---

## 11. Implementation Phases

The implementation is divided into four phases, each delivering a shippable increment. Each phase can be merged independently.

### Phase 1: Authentication (Week 1–2)

- Add `AuthenticationManager` with Sign in with Apple flow
- Create `UserProfile` SwiftData model
- Build `OnboardingView` with sign-in button and guest mode skip
- Add Account section to `SettingsView` (profile display, sign out)
- Persist Apple user ID in Keychain
- **Gate:** user can sign in, see their profile, sign out, and re-authenticate silently

### Phase 2: Sync Infrastructure (Week 3–4)

- Add `ArticleState` and `UserPreferences` SwiftData models
- Modify `ModelContainer` setup for conditional CloudKit configuration
- Update `SwiftDataService` to read/write `ArticleState` on every state change
- Build `SyncService` to monitor CloudKit events and expose sync state
- Add `SyncStatusView` component to Settings
- **Gate:** signed-in user sees sync status; data model is CloudKit-ready but not yet syncing

### Phase 3: CloudKit Sync (Week 5–6)

- Enable `cloudKitDatabase: .automatic` on `ModelConfiguration`
- Implement conflict resolution merge policy for `ArticleState`
- Build feed deduplication logic on CloudKit import events
- Handle cascade delete orphans in `SyncService`
- Add selective `CachedArticle` sync (< 2 MB threshold)
- **Gate:** two devices with same Apple ID see synced feeds, folders, read state, and bookmarks

### Phase 4: Migration & Polish (Week 7–8)

- Build `MigrationService` for local-to-cloud data migration
- Implement store archival and 30-day rollback safety net
- Add sync error handling UI (retry, error details)
- Performance testing with 100+ feeds and 5,000+ article states
- Edge case testing: airplane mode, iCloud storage full, account revocation
- **Gate:** existing users can sign in and have all their data synced without data loss

---

## 12. Testing Strategy

| Test Category | Approach | Tools |
|---------------|----------|-------|
| Unit Tests | `AuthenticationManager` state machine, `ArticleState` merge logic, `MigrationService` data integrity | XCTest, in-memory `ModelContainer` |
| Integration Tests | CloudKit round-trip (write on device A, verify on device B) | Two physical devices, CloudKit development environment |
| Conflict Tests | Simultaneous edits in airplane mode, then reconnect | Two devices, network conditioner |
| Migration Tests | Pre-populated local store migrated to CloudKit store | Archived test databases, XCTest |
| Performance Tests | Sync latency with 100 feeds, 5K article states | XCTest measure blocks, Instruments |
| Edge Cases | iCloud full, account revoked mid-sync, 0 network | Manual QA, simulated conditions |

---

## 13. Risks & Open Questions

| Risk / Question | Severity | Mitigation / Status |
|-----------------|----------|---------------------|
| SwiftData + CloudKit maturity | Medium | SwiftData CloudKit is stable as of iOS 17.4+. Monitor WWDC 2026 for improvements. |
| Initial sync delay on new devices | Low | RSS cache pre-populates UI. Sync completes in background. |
| iCloud storage quota | Medium | `CachedArticle` sync is size-gated (< 2 MB). Article content is not synced. |
| UUID collision on feed dedup | Low | `feedURL` is the true unique key. UUIDs only affect local references. |
| Future: non-Apple auth? | Open | Architecture supports adding email/password later via a separate auth provider. `AuthenticationManager` abstracts the provider. |
| Future: shared folders? | Open | CloudKit shared databases could enable this. Not in current scope. |
