//
//  AuthenticationManager.swift
//  Payam
//
//  @Observable singleton managing the Sign in with Apple lifecycle.
//  Tracks auth state, handles credential checks, and coordinates
//  with SwiftData for UserProfile persistence.
//

import Foundation
import AuthenticationServices
import SwiftData

// MARK: - AuthState

/// Represents the current authentication state of the app.
enum AuthState: Equatable {
    /// Initial state before credential check completes.
    case unknown
    /// User is not signed in (or chose guest mode).
    case signedOut
    /// User has an active Sign in with Apple session.
    case signedIn(appleUserID: String)

    static func == (lhs: AuthState, rhs: AuthState) -> Bool {
        switch (lhs, rhs) {
        case (.unknown, .unknown):     return true
        case (.signedOut, .signedOut): return true
        case (.signedIn(let a), .signedIn(let b)): return a == b
        default: return false
        }
    }
}

// MARK: - AuthenticationManager

@Observable
final class AuthenticationManager {

    // MARK: - Singleton

    static let shared = AuthenticationManager()

    // MARK: - Published State

    /// The current auth state. Views observe this to decide what to show.
    private(set) var state: AuthState = .unknown

    /// The full UserProfile from SwiftData, available after sign-in.
    private(set) var currentUser: UserProfile?

    /// Debug toggle: simulate premium tier without a real subscription.
    /// Set to true in debug builds to test cloud features.
    #if DEBUG
    var debugForcePremium: Bool = false {
        didSet {
            if debugForcePremium {
                // Store a long-lived debug JWT so API calls authenticate
                let debugJWT = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiJkZWJ1Zy11c2VyIiwidGllciI6InByZW1pdW0iLCJpYXQiOjE3NzkyNDUwOTUsImV4cCI6MTgxMDc4MTA5NX0.jtA-JoFFGc3fZA8eKUlI7dcaMX8dsIvm6TL0jBJAKA8"
                KeychainService.saveJWT(debugJWT)
            } else {
                KeychainService.deleteJWT()
            }
        }
    }
    #endif

    /// The current subscription tier, derived from UserProfile.
    var subscriptionTier: SubscriptionTier {
        #if DEBUG
        if debugForcePremium { return .premium }
        #endif
        return currentUser?.subscriptionTier ?? .free
    }

    /// Whether the user explicitly chose to skip sign-in (guest mode).
    /// Must be a stored property so `@Observable` can track it for SwiftUI.
    /// Synced to UserDefaults so the choice persists across launches.
    private(set) var hasSkippedSignIn: Bool = UserDefaults.standard.bool(forKey: "openrss_guest_mode") {
        didSet { UserDefaults.standard.set(hasSkippedSignIn, forKey: "openrss_guest_mode") }
    }

    // MARK: - Computed

    var isSignedIn: Bool {
        if case .signedIn = state { return true }
        return false
    }

    /// Whether the onboarding screen should be shown.
    /// True only when: not signed in, not in guest mode, and initial check is done.
    var shouldShowOnboarding: Bool {
        state == .signedOut && !hasSkippedSignIn
    }

    // MARK: - Internal

    private var modelContext: ModelContext?

    // MARK: - Init

    private init() {}

    // MARK: - Bootstrap

    /// Called once from PayamApp after the ModelContainer is created.
    /// Checks for an existing Apple credential and loads the UserProfile if valid.
    @MainActor
    func configure(container: ModelContainer) {
        self.modelContext = container.mainContext
    }

    /// Checks the stored Apple credential state on launch.
    /// If valid, transitions to `.signedIn`. If revoked or not found, `.signedOut`.
    @MainActor
    func checkExistingCredential() async {
        guard let storedUserID = KeychainService.loadAppleUserID() else {
            state = .signedOut
            return
        }

        do {
            let credentialState = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<ASAuthorizationAppleIDProvider.CredentialState, Error>) in
                ASAuthorizationAppleIDProvider().getCredentialState(forUserID: storedUserID) { state, error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume(returning: state)
                    }
                }
            }

            switch credentialState {
            case .authorized:
                loadUserProfile(appleUserID: storedUserID)
                state = .signedIn(appleUserID: storedUserID)
            case .revoked, .notFound:
                // Credential is no longer valid
                KeychainService.deleteAppleUserID()
                state = .signedOut
            case .transferred:
                // Account was transferred to a different team
                KeychainService.deleteAppleUserID()
                state = .signedOut
            @unknown default:
                state = .signedOut
            }
        } catch {
            // Network error during credential check — assume still valid
            // to avoid locking out users in airplane mode.
            loadUserProfile(appleUserID: storedUserID)
            state = .signedIn(appleUserID: storedUserID)
        }
    }

    // MARK: - Sign In

    /// Performs the Sign in with Apple authorization flow.
    /// On success, persists the credential and creates/updates the UserProfile.
    @MainActor
    func signIn(with authorization: ASAuthorization) {
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
            return
        }

        let userID = credential.user

        // Apple only provides name/email on the FIRST sign-in.
        // On subsequent sign-ins these are nil.
        let fullName = [credential.fullName?.givenName, credential.fullName?.familyName]
            .compactMap { $0 }
            .joined(separator: " ")
        let displayName = fullName.isEmpty ? nil : fullName
        let email = credential.email

        // Persist to Keychain
        KeychainService.saveAppleUserID(userID)

        // Create or update UserProfile in SwiftData
        upsertUserProfile(
            appleUserID: userID,
            displayName: displayName,
            email: email
        )

        // Clear guest mode flag if it was set
        hasSkippedSignIn = false

        state = .signedIn(appleUserID: userID)

        // Exchange Apple identity token for cloud JWT (non-blocking)
        if let identityToken = credential.identityToken {
            Task {
                await exchangeCloudToken(identityToken: identityToken, appleUserID: userID)
            }
        }

        NotificationCenter.default.post(name: Notification.Name("Payam.AuthStateChanged"), object: nil)
    }

    // MARK: - Sign Out

    /// Exchanges the Apple identity token for a cloud JWT and updates the user's tier.
    /// Called after sign-in and on app launch if a valid Apple credential exists.
    @MainActor
    func exchangeCloudToken(identityToken: Data, appleUserID: String) async {
        do {
            let authResponse = try await CloudAuthService.exchangeAppleToken(
                identityToken: identityToken,
                appleUserID: appleUserID
            )

            if let tier = SubscriptionTier(rawValue: authResponse.tier) {
                currentUser?.subscriptionTier = tier
            }
            if let tierExpiry = authResponse.tierExpiresAt {
                currentUser?.premiumExpiresAt = Date(timeIntervalSince1970: tierExpiry)
            }
            try? modelContext?.save()
        } catch {
            print("Cloud auth exchange failed: \(error.localizedDescription)")
        }
    }

    /// Updates the user's subscription tier from StoreKit entitlements.
    @MainActor
    func updateTierFromStoreKit() {
        let tier = StoreKitService.shared.currentTier
        guard currentUser?.subscriptionTier != tier else { return }
        currentUser?.subscriptionTier = tier
        try? modelContext?.save()
    }

    /// Signs the user out, clears credentials, and transitions to `.signedOut`.
    @MainActor
    func signOut() {
        KeychainService.deleteAppleUserID()
        CloudAuthService.clearToken()
        currentUser = nil
        state = .signedOut

        NotificationCenter.default.post(name: Notification.Name("Payam.AuthStateChanged"), object: nil)
    }

    // MARK: - Guest Mode

    /// User chose to skip sign-in. They can sign in later from Settings.
    func skipSignIn() {
        hasSkippedSignIn = true
        state = .signedOut
    }

    // MARK: - Private: UserProfile CRUD

    /// Loads the UserProfile for the given Apple user ID from SwiftData.
    @MainActor
    private func loadUserProfile(appleUserID: String) {
        guard let context = modelContext else { return }

        let descriptor = FetchDescriptor<UserProfile>(
            predicate: #Predicate { $0.appleUserID == appleUserID }
        )

        currentUser = try? context.fetch(descriptor).first
    }

    /// Creates a new UserProfile or updates an existing one.
    /// Only updates displayName/email if non-nil (Apple provides these once).
    @MainActor
    private func upsertUserProfile(appleUserID: String, displayName: String?, email: String?) {
        guard let context = modelContext else { return }

        let descriptor = FetchDescriptor<UserProfile>(
            predicate: #Predicate { $0.appleUserID == appleUserID }
        )

        if let existing = try? context.fetch(descriptor).first {
            // Only overwrite if Apple provided new values (first sign-in)
            if let displayName { existing.displayName = displayName }
            if let email { existing.emailRelay = email }
            currentUser = existing
        } else {
            let profile = UserProfile(
                appleUserID: appleUserID,
                displayName: displayName,
                emailRelay: email
            )
            context.insert(profile)
            try? context.save()
            currentUser = profile
        }
    }
}
