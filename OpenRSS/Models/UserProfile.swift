//
//  UserProfile.swift
//  OpenRSS
//
//  SwiftData persistent model representing an authenticated user.
//  Stores the Apple Sign-In identity and sync metadata.
//

import Foundation
import SwiftData

/// A persisted user profile created after a successful Sign in with Apple.
@Model
final class UserProfile {

    // MARK: - Persisted Properties

    /// The stable Apple user identifier returned by ASAuthorization.
    /// Used as the primary key for identity across sessions and devices.
    @Attribute(.unique) var appleUserID: String

    /// The user's display name (given + family) provided on first sign-in.
    /// Apple only provides this once — subsequent sign-ins return nil.
    var displayName: String?

    /// The private email relay address (e.g. "abc@privaterelay.appleid.com")
    /// or the user's real email if they chose to share it.
    var emailRelay: String?

    /// Optional avatar image data (reserved for future profile customization).
    var avatarData: Data?

    /// When the user first signed in.
    var createdAt: Date

    /// Timestamp of the last successful CloudKit sync round-trip.
    var lastSyncedAt: Date?

    /// Master toggle for iCloud sync. When false, data stays local-only.
    var syncEnabled: Bool

    // MARK: - Initialization

    init(
        appleUserID: String,
        displayName: String? = nil,
        emailRelay: String? = nil,
        syncEnabled: Bool = true
    ) {
        self.appleUserID = appleUserID
        self.displayName = displayName
        self.emailRelay = emailRelay
        self.createdAt = Date()
        self.syncEnabled = syncEnabled
    }
}
