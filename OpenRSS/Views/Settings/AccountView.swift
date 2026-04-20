//
//  AccountView.swift
//  OpenRSS
//
//  Account management screen accessible from Settings.
//  Shows profile info, sync status, and sign-out option.
//

import SwiftUI
import AuthenticationServices

/// Detailed account management view.
///
/// Signed-in users see their profile, sync toggle, and sign-out button.
/// Guest users see a prompt to sign in with Apple.
struct AccountView: View {

    // MARK: - Environment

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss)     private var dismiss

    // MARK: - State

    @State private var showSignOutConfirmation = false
    @State private var showError = false
    @State private var errorMessage = ""

    private var authManager: AuthenticationManager { .shared }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Design.Spacing.section) {
                    if authManager.isSignedIn {
                        signedInContent
                    } else {
                        guestContent
                    }
                }
                .padding(.top, Design.Spacing.edge)
            }
            .background(Design.Colors.background(for: colorScheme))
            .navigationTitle("Account")
            .navigationBarTitleDisplayMode(.inline)
        }
        .alert("Sign Out", isPresented: $showSignOutConfirmation) {
            Button("Sign Out", role: .destructive) {
                authManager.signOut()
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your data will remain on this device but will no longer sync to iCloud. You can sign in again at any time.")
        }
        .alert("Sign In Failed", isPresented: $showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
    }

    // MARK: - Signed In Content

    private var signedInContent: some View {
        VStack(spacing: Design.Spacing.section) {
            // Profile card
            profileCard

            // Sync section
            syncSection

            // Sign out
            signOutSection
        }
    }

    private var profileCard: some View {
        VStack(spacing: 16) {
            // Avatar
            Image(systemName: "person.crop.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(Design.Colors.primary)

            // Name
            if let name = authManager.currentUser?.displayName, !name.isEmpty {
                Text(name)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Design.Colors.primaryText(for: colorScheme))
            }

            // Email
            if let email = authManager.currentUser?.emailRelay, !email.isEmpty {
                Text(email)
                    .font(.system(size: 14))
                    .foregroundStyle(Design.Colors.secondaryText(for: colorScheme))
            }

            // Member since
            if let createdAt = authManager.currentUser?.createdAt {
                Text("Member since \(createdAt.formatted(.dateTime.month(.wide).year()))")
                    .font(.system(size: 13))
                    .foregroundStyle(Design.Colors.secondaryText(for: colorScheme).opacity(0.7))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .background(Design.Colors.cardBackground(for: colorScheme))
        .clipShape(RoundedRectangle(cornerRadius: Design.Radius.standard))
        .overlay(
            RoundedRectangle(cornerRadius: Design.Radius.standard)
                .stroke(
                    colorScheme == .dark
                        ? Design.Colors.subtleBorder
                        : Color.black.opacity(0.08),
                    lineWidth: 1
                )
        )
        .padding(.horizontal, Design.Spacing.edge)
    }

    private var syncSection: some View {
        settingsSection(title: "iCloud Sync", icon: "icloud.fill") {
            VStack(spacing: 0) {
                HStack {
                    Text("Sync Enabled")
                        .font(.system(size: 16))
                        .foregroundStyle(Design.Colors.primaryText(for: colorScheme))

                    Spacer()

                    // Placeholder toggle — functional sync comes in Phase 2
                    Image(systemName: "checkmark.icloud")
                        .font(.system(size: 16))
                        .foregroundStyle(Design.Colors.primary)
                }
                .padding(.horizontal, Design.Spacing.edge)
                .padding(.vertical, 14)

                divider

                HStack {
                    Text("Status")
                        .font(.system(size: 16))
                        .foregroundStyle(Design.Colors.primaryText(for: colorScheme))

                    Spacer()

                    Text("Coming soon")
                        .font(.system(size: 14))
                        .foregroundStyle(Design.Colors.secondaryText(for: colorScheme))
                }
                .padding(.horizontal, Design.Spacing.edge)
                .padding(.vertical, 14)
            }
        }
    }

    private var signOutSection: some View {
        Button {
            showSignOutConfirmation = true
        } label: {
            Text("Sign Out")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.red)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Design.Colors.cardBackground(for: colorScheme))
                .clipShape(RoundedRectangle(cornerRadius: Design.Radius.standard))
                .overlay(
                    RoundedRectangle(cornerRadius: Design.Radius.standard)
                        .stroke(
                            colorScheme == .dark
                                ? Design.Colors.subtleBorder
                                : Color.black.opacity(0.08),
                            lineWidth: 1
                        )
                )
        }
        .buttonStyle(.plain)
        .padding(.horizontal, Design.Spacing.edge)
    }

    // MARK: - Guest Content

    private var guestContent: some View {
        VStack(spacing: Design.Spacing.section) {
            VStack(spacing: 16) {
                Image(systemName: "person.crop.circle.badge.plus")
                    .font(.system(size: 48))
                    .foregroundStyle(Design.Colors.secondaryText(for: colorScheme))

                Text("No Account")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Design.Colors.primaryText(for: colorScheme))

                Text("Sign in with Apple to sync your feeds, bookmarks, and reading progress across all your devices.")
                    .font(.system(size: 15))
                    .foregroundStyle(Design.Colors.secondaryText(for: colorScheme))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 32)

            SignInWithAppleButton(.signIn, onRequest: configureRequest, onCompletion: handleResult)
                .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
                .frame(height: 52)
                .clipShape(RoundedRectangle(cornerRadius: Design.Radius.standard))
                .padding(.horizontal, Design.Spacing.edge)
        }
    }

    // MARK: - Apple Sign In

    private func configureRequest(_ request: ASAuthorizationAppleIDRequest) {
        request.requestedScopes = [.fullName, .email]
    }

    private func handleResult(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let authorization):
            authManager.signIn(with: authorization)
        case .failure(let error):
            if let authError = error as? ASAuthorizationError,
               authError.code == .canceled {
                return
            }
            errorMessage = error.localizedDescription
            showError = true
        }
    }

    // MARK: - Helpers

    private func settingsSection<Content: View>(
        title: String,
        icon: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: Design.Spacing.small) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Design.Colors.primary)

                Text(title.uppercased())
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Design.Colors.secondaryText(for: colorScheme))
                    .tracking(0.5)
            }
            .padding(.horizontal, Design.Spacing.edge)

            content()
                .background(Design.Colors.cardBackground(for: colorScheme))
                .clipShape(RoundedRectangle(cornerRadius: Design.Radius.standard))
                .overlay(
                    RoundedRectangle(cornerRadius: Design.Radius.standard)
                        .stroke(
                            colorScheme == .dark
                                ? Design.Colors.subtleBorder
                                : Color.black.opacity(0.08),
                            lineWidth: 1
                        )
                )
                .padding(.horizontal, Design.Spacing.edge)
        }
    }

    private var divider: some View {
        Rectangle()
            .fill(Design.Colors.subtleBorder)
            .frame(height: 1)
            .padding(.leading, Design.Spacing.edge)
    }
}

// MARK: - Preview

#Preview {
    AccountView()
}
