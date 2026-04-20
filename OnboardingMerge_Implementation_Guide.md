# Onboarding / Auth Integration Guide
## Merging `feature/auth-phase1` into `main`

**Project:** OpenRSS (AppleRSS)
**Remote:** https://github.com/dsehsani/apple-rss-reader.git
**Branch to merge:** `origin/feature/auth-phase1`
**Target branch:** `main`

---

## What the Auth Branch Adds

These are net-new files that do not exist in `main` at all — they come across cleanly with no conflict:

| File | Purpose |
|---|---|
| `OpenRSS/Models/UserProfile.swift` | SwiftData model — stores `appleUserID`, `displayName`, `emailRelay`, `syncEnabled`, `lastSyncedAt` |
| `OpenRSS/Services/AuthenticationManager.swift` | `@Observable` singleton — manages Sign in with Apple lifecycle, credential checks, guest mode |
| `OpenRSS/Services/KeychainService.swift` | Secure Keychain wrapper — persists Apple user ID across reinstalls |
| `OpenRSS/Views/Onboarding/OnboardingView.swift` | Full-screen welcome screen with Sign in with Apple + "Continue without account" |
| `OpenRSS/Views/Settings/AccountView.swift` | Account management sheet — profile card, sync status, sign-out |

---

## Critical Warning: Do NOT Do a Straight Merge

The auth branch contains an **older version of `OpenRSSApp.swift`** and **an older version of `SettingsView.swift`** that are missing work already done on `main`. A straight `git merge` will produce conflicts, and accepting the branch version wholesale will **delete**:

- All Background App Refresh code (`BGTaskScheduler`, `handleRiverRefresh`, `scheduleNextRiverRefresh`, `isNetworkAvailable`, `RefreshStateStore` wiring)
- OPML import/export state and buttons in `SettingsView`
- The `affinitySection` (Source Affinity nav link) in `SettingsView`
- `import BackgroundTasks`, `import Network`, `import UniformTypeIdentifiers`

The correct approach is to **cherry-pick the new files** and **manually apply the auth additions** to the existing `main` versions of the two conflicted files. This guide covers exactly that.

---

## Step 1: Set Up the Branch Locally

```bash
git fetch origin
git checkout main
git pull origin main
```

Do not run `git merge feature/auth-phase1`. Work manually as described below.

---

## Step 2: Copy the Five New Files from the Auth Branch

Run these commands to extract the new files directly from the remote branch without merging:

```bash
git checkout origin/feature/auth-phase1 -- OpenRSS/Models/UserProfile.swift
git checkout origin/feature/auth-phase1 -- OpenRSS/Services/AuthenticationManager.swift
git checkout origin/feature/auth-phase1 -- OpenRSS/Services/KeychainService.swift
git checkout origin/feature/auth-phase1 -- OpenRSS/Views/Onboarding/OnboardingView.swift
git checkout origin/feature/auth-phase1 -- OpenRSS/Views/Settings/AccountView.swift
```

These files are clean additions. Add them to the Xcode project target (OpenRSS target, not tests).

---

## Step 3: Update OpenRSSApp.swift

This is the most important conflict. The auth branch's `OpenRSSApp.swift` stripped all BGTask code. The final file must have **both** the auth additions AND the background task code from `main`.

Apply these changes to the **current `main` version** of `OpenRSSApp.swift`:

### 3a — Add `UserProfile` to the schema

Find:
```swift
let schema = Schema([FolderModel.self, FeedModel.self, CachedArticle.self])
```

Replace with:
```swift
let schema = Schema([
    FolderModel.self,
    FeedModel.self,
    CachedArticle.self,
    UserProfile.self,
])
```

### 3b — Bootstrap `AuthenticationManager` alongside `SwiftDataService`

Find:
```swift
MainActor.assumeIsolated {
    SwiftDataService.shared.configure(container: container)

    // Pre-warm the WKWebView pool so the first article open is fast.
    WebViewPool.shared.warmUp()
}
```

Replace with:
```swift
MainActor.assumeIsolated {
    SwiftDataService.shared.configure(container: container)
    AuthenticationManager.shared.configure(container: container)

    // Pre-warm the WKWebView pool so the first article open is fast.
    WebViewPool.shared.warmUp()
}
```

### 3c — Add auth state property and credential check task

Find:
```swift
// MARK: - App State

@State private var appState = AppState()
```

Replace with:
```swift
// MARK: - App State

@State private var appState = AppState()
@State private var hasCheckedAuth = false
```

### 3d — Replace the WindowGroup body to add auth routing and credential check

Find the `.task` modifier or the `body` scene — add the credential check task and route between `OnboardingView` and `MainTabView`.

The `body` property should become:

```swift
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
```

> **Important:** The existing `didEnterBackgroundNotification` handler that calls `scheduleNextRiverRefresh()` must be kept. The auth branch deleted it — do not delete it.

### 3e — Keep all BGTask code exactly as-is

The following methods must remain untouched in `OpenRSSApp.swift`. The auth branch deleted them — restore from `main` if they were lost:

- `private static let riverRefreshIdentifier`
- `private static func registerBackgroundTasks()`
- `private static func handleRiverRefresh(task:)`
- `private static func isNetworkAvailable() async -> Bool`
- `static func scheduleNextRiverRefresh()`
- The `Self.registerBackgroundTasks()` call at the end of `init()`
- `import BackgroundTasks` and `import Network` at the top

---

## Step 4: Update SettingsView.swift

The auth branch modified `SettingsView.swift` to add the account section but also removed OPML and RefreshStateStore work. Apply only the additions, leave everything else from `main` intact.

### 4a — Add auth state properties (keep existing state, add to it)

The file currently has (from `main`):
```swift
private var refreshStore = RefreshStateStore.shared
@State private var showImages: Bool = true
// ... other state
// OPML
@State private var isImporting = false
@State private var showExportPicker = false
@State private var exportItem: ExportFileItem? = nil
@State private var opmlAlert: OPMLAlertItem? = nil
```

Add two new lines after the OPML block:
```swift
// Account
@State private var showAccountView: Bool = false
private var authManager: AuthenticationManager { .shared }
```

### 4b — Add the `.sheet` for AccountView to both body branches

In `liquidGlassBody`, the `NavigationStack` already has modifiers. Add:
```swift
.sheet(isPresented: $showAccountView) {
    AccountView()
}
```

Do the same in `legacyBody`'s outer `ZStack`.

### 4c — Add `accountSection` to both body VStacks

In both `liquidGlassBody` and `legacyBody`, the sections VStack currently reads:
```swift
VStack(spacing: Design.Spacing.section) {
    appearanceSection
    readingSection
    affinitySection
    dataSection
    aboutSection
}
```

Add `accountSection` as the first item:
```swift
VStack(spacing: Design.Spacing.section) {
    accountSection      // ← add this
    appearanceSection
    readingSection
    affinitySection     // ← keep this, the auth branch deleted it — restore it
    dataSection
    aboutSection
}
```

### 4d — Add the `accountSection` computed property

Add this computed property to `SettingsView`, after `legacyHeaderView` and before `appearanceSection`:

```swift
// MARK: - Account Section

private var accountSection: some View {
    settingsSection(title: "Account", icon: "person.circle.fill") {
        Button {
            showAccountView = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: authManager.isSignedIn
                    ? "person.crop.circle.fill"
                    : "person.crop.circle.badge.plus")
                    .font(.system(size: 32))
                    .foregroundStyle(authManager.isSignedIn
                        ? Design.Colors.primary
                        : Design.Colors.secondaryText(for: colorScheme))

                VStack(alignment: .leading, spacing: 2) {
                    if authManager.isSignedIn {
                        Text(authManager.currentUser?.displayName ?? "Apple ID User")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Design.Colors.primaryText(for: colorScheme))
                        Text("iCloud sync available")
                            .font(.system(size: 13))
                            .foregroundStyle(Design.Colors.secondaryText(for: colorScheme))
                    } else {
                        Text("Sign In")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Design.Colors.primaryText(for: colorScheme))
                        Text("Sync feeds across your devices")
                            .font(.system(size: 13))
                            .foregroundStyle(Design.Colors.secondaryText(for: colorScheme))
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Design.Colors.secondaryText(for: colorScheme).opacity(0.5))
            }
            .padding(.horizontal, Design.Spacing.edge)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
```

---

## Step 5: Add Xcode Capability — Sign in with Apple

This cannot be done in code — it must be done in Xcode:

1. Open `OpenRSS.xcodeproj`
2. Select the `OpenRSS` target → **Signing & Capabilities**
3. Click **+ Capability**
4. Add **Sign in with Apple**

Without this, `ASAuthorizationAppleIDProvider` will silently fail at runtime.

---

## Step 6: Verify the Build

After all changes, confirm:

1. **Schema includes `UserProfile`** — check `OpenRSSApp.init()` has all four models in the `Schema([...])` call
2. **BGTask still registered** — `Self.registerBackgroundTasks()` is called in `init()`
3. **Auth check fires on launch** — `.task { await AuthenticationManager.shared.checkExistingCredential() }` is on the root view
4. **Onboarding routes correctly** — `rootView` switches on `auth.state`
5. **SettingsView has all sections** — account, appearance, reading, affinitySection, data (with OPML buttons), about
6. **OPML state vars present** — `isImporting`, `showExportPicker`, `exportItem`, `opmlAlert` all still in SettingsView
7. **RefreshStateStore binding** — `refreshStore = RefreshStateStore.shared` still drives the interval picker
8. Build and run — confirm no "Missing type" or "Use of unresolved identifier" errors

---

## Step 7: Functional Testing Checklist

**First launch (no prior credential):**
- [ ] `OnboardingView` appears
- [ ] "Sign in with Apple" sheet appears on tap, credential flow completes
- [ ] After sign-in, `MainTabView` is shown (not onboarding again)
- [ ] `UserProfile` record created in SwiftData with correct `appleUserID`, `displayName`, `emailRelay`

**Guest mode:**
- [ ] "Continue without account" tap dismisses onboarding → `MainTabView` shown
- [ ] Re-launching the app does NOT show onboarding again (guest flag persisted in UserDefaults)

**Settings → Account:**
- [ ] Signed-in state shows avatar, display name, "iCloud sync available"
- [ ] Guest state shows "Sign In" prompt and Sign in with Apple button
- [ ] Sign Out button shows confirmation alert → signs out → account section reverts to guest state

**Returning user (credential already stored):**
- [ ] App launches directly to `MainTabView` with no onboarding flash
- [ ] `AuthenticationManager.shared.state` is `.signedIn` after `.checkExistingCredential()`

**Background refresh still works:**
- [ ] App entering background still schedules BGTask (check console: no "BGTask scheduling failed")
- [ ] Simulate BGTask in Xcode debugger — pipeline runs and `RefreshStateStore.shared.lastRefreshedAt` is set

---

## Notes for the Agent

- The branch name on remote is `feature/auth-phase1` (no dash before "1") — confirm with `git branch -a` before checking out.
- Never overwrite `OpenRSSApp.swift` with the auth branch version wholesale. The auth branch version is missing ~80 lines of BGTask code.
- `AuthenticationManager` is `@Observable` — consistent with `SwiftDataService`. Access it via `.shared` singleton, not via `@Environment`.
- `UserProfile` has `@Attribute(.unique)` on `appleUserID` — SwiftData enforces uniqueness. The `upsertUserProfile` method in `AuthenticationManager` handles the insert-or-update pattern correctly; do not add duplicate insert logic.
- Apple only provides `fullName` and `email` on the **first** Sign in with Apple. On subsequent sign-ins these are `nil`. The `upsertUserProfile` method handles this by only overwriting when non-nil — do not change this behavior.
- `KeychainService` uses `kSecAttrAccessibleAfterFirstUnlock` so credentials survive device restart before first unlock (important for background task scenarios).
- The `affinitySection` was removed in the auth branch — this was accidental and must be restored. It contains the `NavigationLink` to `SourceAffinityView`.
