//
//  PremiumGate.swift
//  Payam
//
//  Single source of truth for the Premium / Basic mode check used by every
//  call site that talks to an OpenRSS-owned backend (CloudKit, /v1/river,
//  /v1/feeds, /v1/agent, /v1/extractions).
//
//  Reads UserDefaults directly so it's safe to call before SwiftData is
//  ready (PayamApp.init reads Premium status during ModelContainer setup).
//  Defaults to `true` on a fresh install so new users land on Premium.
//

import Foundation

enum PremiumGate {

    /// UserDefaults key used by the Settings toggle (`SettingsView` writes here)
    /// and by every gating call site below.
    static let userDefaultsKey = "payam.isPremium"

    /// True when the user is on Premium. Reads the UserDefaults mirror written
    /// by the Settings toggle. SwiftData's `UserPreferences.isPremium` is the
    /// long-term source of truth, but the toggle keeps the UserDefaults mirror
    /// in sync so this stays cheap and usable from non-MainActor contexts.
    static var isPremium: Bool {
        UserDefaults.standard.object(forKey: userDefaultsKey) as? Bool ?? true
    }
}
