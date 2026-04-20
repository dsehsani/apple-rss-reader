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
