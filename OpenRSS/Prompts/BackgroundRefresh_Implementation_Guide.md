# Background App Refresh Enhancements — Implementation Guide

**Project:** OpenRSS (AppleRSS)
**Target:** iOS 17+, SwiftUI, SwiftData
**Scope:** Enhance the existing BGAppRefreshTask implementation with persistent state, a working refresh interval picker, network-aware scheduling, and user-visible last-updated feedback.

---

## Current State

The background refresh is already scaffolded in `OpenRSSApp.swift`. Here is exactly what exists and what is missing:

**What exists:**
- `BGAppRefreshTask` registered with identifier `com.openrss.riverRefresh`
- `handleRiverRefresh(task:)` calls `RiverPipeline.shared.runCycle(sources:)`
- `scheduleNextRiverRefresh()` hardcodes a 30-minute interval
- `UIApplication.didEnterBackgroundNotification` triggers scheduling
- `Info.plist` has `UIBackgroundModes = fetch` and the task identifier — no changes needed
- `SettingsView` has a `RefreshInterval` picker (`@State private var refreshInterval`) — but it is **purely cosmetic**, wired to nothing

**What is missing:**
1. The `RefreshInterval` picker is not persisted and has no effect on the actual schedule
2. No record of when the last refresh occurred
3. No network check — the pipeline runs even with no connection
4. No user-visible "Last updated" feedback in Settings
5. No backoff when no new articles are found

---

## Files to Modify

```
OpenRSS/OpenRSSApp.swift                     ← scheduling logic
OpenRSS/Views/Settings/SettingsView.swift    ← wire picker + show last-updated
```

One new file:

```
OpenRSS/Services/RefreshStateStore.swift     ← UserDefaults wrapper for refresh state
```

---

## Part 1: RefreshStateStore.swift

Create this file at `OpenRSS/Services/RefreshStateStore.swift`.

This is a lightweight `@Observable` UserDefaults wrapper. It is the single source of truth for refresh interval and last-refresh timestamp. Both `OpenRSSApp` and `SettingsView` read from it.

```swift
//
//  RefreshStateStore.swift
//  OpenRSS
//
//  Persistent state for background refresh scheduling.
//  Backed by UserDefaults. Observable so SettingsView updates live.
//

import Foundation
import Observation

@Observable
final class RefreshStateStore {

    // MARK: - Singleton

    static let shared = RefreshStateStore()

    // MARK: - UserDefaults Keys

    private enum Keys {
        static let refreshInterval  = "openrss.refreshInterval"
        static let lastRefreshedAt  = "openrss.lastRefreshedAt"
        static let consecutiveEmpty = "openrss.consecutiveEmptyRefreshes"
    }

    // MARK: - Observable Properties

    /// The user-selected refresh interval. Persisted to UserDefaults.
    var refreshInterval: RefreshInterval {
        get {
            let raw = UserDefaults.standard.string(forKey: Keys.refreshInterval) ?? ""
            return RefreshInterval(rawValue: raw) ?? .thirtyMinutes
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: Keys.refreshInterval)
        }
    }

    /// Timestamp of the last completed refresh cycle. nil if never run.
    var lastRefreshedAt: Date? {
        get {
            let t = UserDefaults.standard.double(forKey: Keys.lastRefreshedAt)
            return t == 0 ? nil : Date(timeIntervalSince1970: t)
        }
        set {
            UserDefaults.standard.set(newValue?.timeIntervalSince1970 ?? 0, forKey: Keys.lastRefreshedAt)
        }
    }

    /// Number of consecutive refresh cycles that produced zero new articles.
    /// Used for exponential backoff.
    var consecutiveEmptyRefreshes: Int {
        get { UserDefaults.standard.integer(forKey: Keys.consecutiveEmpty) }
        set { UserDefaults.standard.set(newValue, forKey: Keys.consecutiveEmpty) }
    }

    private init() {}

    // MARK: - Computed Helpers

    /// Human-readable string for display in SettingsView (e.g. "2 minutes ago").
    var lastRefreshedString: String {
        guard let date = lastRefreshedAt else { return "Never" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    /// The next scheduled interval in seconds, with exponential backoff applied.
    /// Backoff doubles the interval for each consecutive empty refresh, up to 4×.
    var nextIntervalSeconds: TimeInterval {
        guard refreshInterval != .manual else { return .infinity }
        let base = refreshInterval.intervalSeconds
        let multiplier = min(pow(2.0, Double(consecutiveEmptyRefreshes)), 4.0)
        return base * multiplier
    }
}
```

---

## Part 2: RefreshInterval Extension

`RefreshInterval` is defined at the bottom of `SettingsView.swift`. Add an `intervalSeconds` computed property to it so `RefreshStateStore` can use it.

Find this block in `SettingsView.swift`:

```swift
enum RefreshInterval: String, CaseIterable {
    case manual = "Manual"
    case fifteenMinutes = "15 Minutes"
    case thirtyMinutes = "30 Minutes"
    case hourly = "Hourly"
    case daily = "Daily"
}
```

Replace it with:

```swift
enum RefreshInterval: String, CaseIterable {
    case manual         = "Manual"
    case fifteenMinutes = "15 Minutes"
    case thirtyMinutes  = "30 Minutes"
    case hourly         = "Hourly"
    case daily          = "Daily"

    var intervalSeconds: TimeInterval {
        switch self {
        case .manual:         return .infinity
        case .fifteenMinutes: return 15 * 60
        case .thirtyMinutes:  return 30 * 60
        case .hourly:         return 60 * 60
        case .daily:          return 24 * 60 * 60
        }
    }
}
```

---

## Part 3: Update OpenRSSApp.swift

### 3a — Wire RefreshStateStore into scheduling

Replace the current `scheduleNextRiverRefresh()` method:

```swift
// BEFORE
static func scheduleNextRiverRefresh() {
    let request = BGAppRefreshTaskRequest(identifier: riverRefreshIdentifier)
    request.earliestBeginDate = Date(timeIntervalSinceNow: 30 * 60)
    do {
        try BGTaskScheduler.shared.submit(request)
    } catch {
        print("BGTask scheduling failed: \(error)")
    }
}
```

Replace with:

```swift
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
```

### 3b — Record last-refresh timestamp and track empty cycles

Replace the current `handleRiverRefresh(task:)` method:

```swift
// BEFORE
private static func handleRiverRefresh(task: BGAppRefreshTask) {
    scheduleNextRiverRefresh()

    let workTask = Task {
        let sources = await MainActor.run { SwiftDataService.shared.sources }
        await RiverPipeline.shared.runCycle(sources: sources)
        task.setTaskCompleted(success: true)
    }

    task.expirationHandler = {
        workTask.cancel()
    }
}
```

Replace with:

```swift
private static func handleRiverRefresh(task: BGAppRefreshTask) {
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

    task.expirationHandler = {
        workTask.cancel()
    }
}
```

### 3c — Add the network check helper

Add this static method inside `OpenRSSApp`, below `handleRiverRefresh`:

```swift
/// Returns true if the device has any usable network path.
/// Uses Network framework for a synchronous-style check via a semaphore.
private static func isNetworkAvailable() async -> Bool {
    await withCheckedContinuation { continuation in
        import Network  // add `import Network` at the top of the file

        let monitor = NWPathMonitor()
        let queue = DispatchQueue(label: "com.openrss.networkCheck")
        monitor.pathUpdateHandler = { path in
            monitor.cancel()
            continuation.resume(returning: path.status == .satisfied)
        }
        monitor.start(queue: queue)
    }
}
```

> **Note:** Add `import Network` to the top of `OpenRSSApp.swift` alongside the existing imports.

---

## Part 4: Add totalItemCount() to SQLiteStore

`handleRiverRefresh` calls `SQLiteStore.shared.totalItemCount()` to detect whether the pipeline produced new items. Add this method to `SQLiteStore.swift`:

```swift
/// Returns the total number of feed items in the database.
/// Used to detect empty pipeline cycles for backoff.
func totalItemCount() -> Int {
    // Assumes the feed_items table exists — safe after first pipeline run.
    let sql = "SELECT COUNT(*) FROM feed_items;"
    var stmt: OpaquePointer?
    var count = 0
    if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
        if sqlite3_step(stmt) == SQLITE_ROW {
            count = Int(sqlite3_column_int(stmt, 0))
        }
    }
    sqlite3_finalize(stmt)
    return count
}
```

> **Note:** If `SQLiteStore` uses a GRDB or SQLite.swift abstraction rather than raw `sqlite3_*` calls, adapt accordingly. Check the existing query pattern in `SQLiteStore.swift` and match it exactly.

---

## Part 5: Update SettingsView.swift

### 5a — Replace the local @State refreshInterval with RefreshStateStore

At the top of `SettingsView`, find:

```swift
@State private var refreshInterval: RefreshInterval = .hourly
```

Replace with:

```swift
private var refreshStore = RefreshStateStore.shared
```

### 5b — Update the picker binding

In `settingsPicker(title:selection:)` inside `dataSection`, the call currently reads:

```swift
settingsPicker(title: "Refresh Interval", selection: $refreshInterval)
```

Replace with:

```swift
settingsPicker(title: "Refresh Interval", selection: Binding(
    get: { refreshStore.refreshInterval },
    set: { refreshStore.refreshInterval = $0 }
))
```

### 5c — Add "Last Updated" row to dataSection

Inside `dataSection`, after the `settingsPicker` row and before the first `divider`, add:

```swift
divider
HStack {
    Text("Last Updated")
        .font(.system(size: 16))
        .foregroundStyle(Design.Colors.primaryText(for: colorScheme))
    Spacer()
    Text(refreshStore.lastRefreshedString)
        .font(.system(size: 16))
        .foregroundStyle(Design.Colors.secondaryText(for: colorScheme))
}
.padding(.horizontal, Design.Spacing.edge)
.padding(.vertical, 14)
```

This will automatically update as `RefreshStateStore` is `@Observable` — no timer or manual refresh needed.

---

## Behavior Summary After All Changes

| Scenario | Behavior |
|---|---|
| User sets interval to "Manual" | `scheduleNextRiverRefresh()` returns early — no BGTask submitted |
| User sets interval to "15 Minutes" | Next BGTask scheduled for 15 min from now |
| Pipeline runs, finds new articles | `consecutiveEmptyRefreshes` reset to 0, next interval = base interval |
| Pipeline runs, finds nothing | `consecutiveEmptyRefreshes` increments, next interval doubles (max 4×) |
| Device has no network | Pipeline skipped, task marked failed, `lastRefreshedAt` not updated |
| App enters background | `scheduleNextRiverRefresh()` fires, reads current interval from UserDefaults |
| User opens Settings | "Last Updated" row shows relative timestamp, live-updating |

---

## Testing Checklist

- [ ] Change interval to "15 Minutes" in Settings → close app → reopen → `RefreshStateStore.shared.refreshInterval` returns `.fifteenMinutes`
- [ ] Simulate BGTask in Xcode debugger (`e -l objc -- (void)[[BGTaskScheduler sharedScheduler] _simulateLaunchForTaskWithIdentifier:@"com.openrss.riverRefresh"]`) → verify pipeline runs and `lastRefreshedAt` is set
- [ ] Set interval to "Manual" → verify no BGTask request is submitted (check console, no "BGTask scheduling failed" and no task fires)
- [ ] Run pipeline with airplane mode on → verify it exits early and `lastRefreshedAt` is not updated
- [ ] Run pipeline twice with no new feeds → verify `consecutiveEmptyRefreshes` is 2 and `nextIntervalSeconds` is 4× the base
- [ ] Run pipeline with new articles → verify `consecutiveEmptyRefreshes` resets to 0
- [ ] Open Settings → "Last Updated" shows correct relative time (e.g. "2 minutes ago")
- [ ] Change interval in Settings → close Settings → reopen → picker shows the saved value (not reverting to default)

---

## Notes for the Agent

- `RefreshStateStore` is `@Observable` (Swift 5.9 observation) — consistent with `SwiftDataService`. Do **not** use `ObservableObject` / `@Published`.
- The `@State private var refreshInterval: RefreshInterval` in `SettingsView` must be **removed** entirely and replaced with the `refreshStore` reference. Leaving both will cause the picker to bind to the in-memory state rather than UserDefaults.
- `NWPathMonitor` is single-use per check — create a new instance each time, call `.cancel()` inside the handler after reading the path. Do not store it as a property.
- The backoff cap of 4× prevents the interval from growing unboundedly. At "Hourly" with 4 empty cycles the max becomes 4 hours — reasonable for a low-traffic feed list.
- `SQLiteStore.shared.totalItemCount()` is used only as a before/after delta proxy. An exact diff is not needed; any positive delta resets the counter.
- `scheduleNextRiverRefresh()` is called both from `handleRiverRefresh` (at the start of the background task) and from the `didEnterBackgroundNotification` handler. Both call paths already exist — no structural changes to `OpenRSSApp.body` are needed.
