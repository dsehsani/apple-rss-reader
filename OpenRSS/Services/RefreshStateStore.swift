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
    /// Backoff doubles the interval for each consecutive empty refresh, up to 4x.
    var nextIntervalSeconds: TimeInterval {
        guard refreshInterval != .manual else { return .infinity }
        let base = refreshInterval.intervalSeconds
        let multiplier = min(pow(2.0, Double(consecutiveEmptyRefreshes)), 4.0)
        return base * multiplier
    }
}
