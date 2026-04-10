//
//  OnboardingView.swift
//  OpenRSS
//
//  Welcome screen with Sign in with Apple and a guest mode option.
//  Shown on first launch before the user has signed in or skipped.
//

import SwiftUI
import AuthenticationServices

/// Full-screen onboarding view with Sign in with Apple.
///
/// Provides two paths:
/// 1. Sign in with Apple → creates a UserProfile and enables future iCloud sync.
/// 2. "Continue without account" → guest mode, local-only data.
struct OnboardingView: View {

    // MARK: - Environment

    @Environment(\.colorScheme) private var colorScheme

    // MARK: - State

    @State private var showError: Bool = false
    @State private var errorMessage: String = ""

    // MARK: - Body

    var body: some View {
        ZStack {
            // Background
            Design.Colors.background(for: colorScheme)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                // App icon and branding
                brandingSection

                Spacer()

                // Feature highlights
                featureList

                Spacer()

                // Sign in button + skip
                actionSection

                Spacer()
                    .frame(height: 40)
            }
            .padding(.horizontal, Design.Spacing.edge)
        }
        .alert("Sign In Failed", isPresented: $showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
    }

    // MARK: - Branding

    private var brandingSection: some View {
        VStack(spacing: 16) {
            // App icon placeholder
            Image(systemName: "dot.radiowaves.left.and.right")
                .font(.system(size: 64, weight: .light))
                .foregroundStyle(Design.Colors.primary)
                .frame(width: 100, height: 100)
                .background(
                    RoundedRectangle(cornerRadius: 24)
                        .fill(Design.Colors.primary.opacity(0.12))
                )

            Text("OpenRSS")
                .font(.system(size: 34, weight: .bold))
                .foregroundStyle(Design.Colors.primaryText(for: colorScheme))

            Text("Your feeds. Your way.")
                .font(.system(size: 17))
                .foregroundStyle(Design.Colors.secondaryText(for: colorScheme))
        }
    }

    // MARK: - Feature List

    private var featureList: some View {
        VStack(alignment: .leading, spacing: 20) {
            featureRow(
                icon: "arrow.triangle.2.circlepath",
                title: "Sync across devices",
                subtitle: "Sign in to keep your feeds, bookmarks, and reading progress in sync via iCloud."
            )
            featureRow(
                icon: "lock.shield",
                title: "Private by design",
                subtitle: "Your data stays in your iCloud account. No third-party servers."
            )
            featureRow(
                icon: "person.crop.circle",
                title: "Optional account",
                subtitle: "Use OpenRSS without signing in. You can always add an account later."
            )
        }
        .padding(.horizontal, 8)
    }

    private func featureRow(icon: String, title: String, subtitle: String) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(Design.Colors.primary)
                .frame(width: 36, height: 36)
                .background(
                    Circle()
                        .fill(Design.Colors.primary.opacity(0.1))
                )

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Design.Colors.primaryText(for: colorScheme))

                Text(subtitle)
                    .font(.system(size: 14))
                    .foregroundStyle(Design.Colors.secondaryText(for: colorScheme))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Action Section

    private var actionSection: some View {
        VStack(spacing: 16) {
            // Sign in with Apple
            SignInWithAppleButton(.signIn, onRequest: configureRequest, onCompletion: handleResult)
                .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
                .frame(height: 52)
                .clipShape(RoundedRectangle(cornerRadius: Design.Radius.standard))

            // Guest mode
            Button {
                AuthenticationManager.shared.skipSignIn()
            } label: {
                Text("Continue without account")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Design.Colors.secondaryText(for: colorScheme))
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
            }
        }
        .padding(.horizontal, 8)
    }

    // MARK: - Apple Sign In

    private func configureRequest(_ request: ASAuthorizationAppleIDRequest) {
        request.requestedScopes = [.fullName, .email]
    }

    private func handleResult(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let authorization):
            AuthenticationManager.shared.signIn(with: authorization)
        case .failure(let error):
            // ASAuthorizationError.canceled means the user dismissed the sheet — not an error.
            if let authError = error as? ASAuthorizationError,
               authError.code == .canceled {
                return
            }
            errorMessage = error.localizedDescription
            showError = true
        }
    }
}

// MARK: - Preview

#Preview {
    OnboardingView()
}
