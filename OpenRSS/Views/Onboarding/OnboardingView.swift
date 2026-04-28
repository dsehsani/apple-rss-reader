//
//  OnboardingView.swift
//  OpenRSS
//
//  Multi-page onboarding with animated mesh gradient background,
//  staggered entrance animations, and Apple Sign In on the final CTA page.
//

import SwiftUI
import AuthenticationServices

// MARK: - Page Data Model

private struct OnboardingPage {
    let icon: String
    let headline: String
    let subheadline: String
    let accentColor: Color
    let animateIcon: Bool
}

private let onboardingPages: [OnboardingPage] = [
    OnboardingPage(
        icon: "dot.radiowaves.left.and.right",
        headline: "Your feeds.\nYour way.",
        subheadline: "A fresh take on RSS. Clean, fast, and built around how you actually read.",
        accentColor: Design.Colors.primary,
        animateIcon: true
    ),
    OnboardingPage(
        icon: "arrow.triangle.2.circlepath.icloud",
        headline: "Everything,\neverywhere.",
        subheadline: "Your feeds, bookmarks, and reading progress stay perfectly in sync across all your devices via iCloud.",
        accentColor: Color(hex: "0A84FF"),   // Apple system blue (lighter sibling of primary)
        animateIcon: false
    ),
    OnboardingPage(
        icon: "lock.shield",
        headline: "Just yours.",
        subheadline: "Your data lives in your iCloud account. No tracking. No ads. No third-party servers.",
        accentColor: Color(hex: "34C759"),   // Apple system green
        animateIcon: false
    ),
]

// MARK: - Root View

struct OnboardingView: View {

    @Environment(\.colorScheme) private var colorScheme

    @State private var currentPage: Int = 0
    @State private var showError: Bool = false
    @State private var errorMessage: String = ""

    private let totalPages = onboardingPages.count + 1  // feature pages + CTA

    var body: some View {
        ZStack(alignment: .bottom) {

            // 1. Animated background
            OnboardingBackground(colorScheme: colorScheme)

            // 2. Page content
            TabView(selection: $currentPage) {
                ForEach(Array(onboardingPages.enumerated()), id: \.offset) { index, page in
                    OnboardingFeaturePage(page: page)
                        .tag(index)
                }
                OnboardingCTAPage(
                    colorScheme: colorScheme,
                    onError: { msg in
                        errorMessage = msg
                        showError = true
                    }
                )
                .tag(onboardingPages.count)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            // 3. Floating bottom controls (dots + next arrow)
            if currentPage < onboardingPages.count {
                OnboardingBottomBar(
                    currentPage: $currentPage,
                    totalPages: totalPages
                )
                .padding(.horizontal, 28)
                .padding(.bottom, 52)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .ignoresSafeArea()
        .animation(.spring(response: 0.45, dampingFraction: 0.82), value: currentPage)
        .alert("Sign In Failed", isPresented: $showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
    }
}

// MARK: - Animated Background

private struct OnboardingBackground: View {
    let colorScheme: ColorScheme

    var body: some View {
        if #available(iOS 18, *) {
            MeshBackground(colorScheme: colorScheme)
        } else {
            GradientBackground(colorScheme: colorScheme)
        }
    }
}

/// iOS 18+ — slow breathing MeshGradient
@available(iOS 18, *)
private struct MeshBackground: View {
    let colorScheme: ColorScheme

    // Dark palette — near-black with the faintest blue breath. Matches new #0C0C0E bg.
    private let darkColors: [Color] = [
        Color(hex: "0C0C0E"), Color(hex: "111318"), Color(hex: "0C0C0E"),
        Color(hex: "121418"), Color(hex: "161A20"), Color(hex: "111318"),
        Color(hex: "0C0C0E"), Color(hex: "0F1114"), Color(hex: "0C0C0E"),
    ]

    // Light palette — clean whites with a whisper of blue
    private let lightColors: [Color] = [
        Color.white, Color(hex: "edf4ff"), Color.white,
        Color(hex: "e8f2ff"), Color(hex: "f0f8ff"), Color(hex: "ecf4ff"),
        Color.white, Color(hex: "f5faff"), Color.white,
    ]

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30)) { timeline in
            let t = Float(timeline.date.timeIntervalSinceReferenceDate)
            let wave  = sin(t * 0.18) * 0.07   // slow, subtle oscillation
            let wave2 = cos(t * 0.12) * 0.05

            MeshGradient(
                width: 3,
                height: 3,
                points: [
                    SIMD2<Float>(0,           0),
                    SIMD2<Float>(0.5,         0),
                    SIMD2<Float>(1,           0),

                    SIMD2<Float>(0,           0.5 + wave),
                    SIMD2<Float>(0.5 + wave2, 0.5),
                    SIMD2<Float>(1,           0.5 - wave),

                    SIMD2<Float>(0,           1),
                    SIMD2<Float>(0.5,         1),
                    SIMD2<Float>(1,           1),
                ],
                colors: colorScheme == .dark ? darkColors : lightColors
            )
        }
        .ignoresSafeArea()
    }
}

/// iOS 17 fallback — animated radial gradient with the same navy/white palette
private struct GradientBackground: View {
    let colorScheme: ColorScheme
    @State private var phase: CGFloat = 0

    var body: some View {
        ZStack {
            (colorScheme == .dark ? Color(hex: "0C0C0E") : Color(hex: "F2F2F7"))
                .ignoresSafeArea()

            RadialGradient(
                colors: colorScheme == .dark
                    ? [Color(hex: "161A20").opacity(0.9), Color.clear]
                    : [Color(hex: "E8F2FF").opacity(0.6), Color.clear],
                center: .init(x: 0.5 + phase * 0.15, y: 0.38),
                startRadius: 0,
                endRadius: 380
            )
            .ignoresSafeArea()
            .onAppear {
                withAnimation(.easeInOut(duration: 7).repeatForever(autoreverses: true)) {
                    phase = 1
                }
            }
        }
    }
}

// MARK: - Feature Page

private struct OnboardingFeaturePage: View {
    let page: OnboardingPage

    @Environment(\.colorScheme) private var colorScheme

    @State private var iconVisible = false
    @State private var headlineVisible = false
    @State private var subtitleVisible = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // Icon with layered glow rings
            iconView
                .scaleEffect(iconVisible ? 1.0 : 0.72)
                .opacity(iconVisible ? 1 : 0)

            Spacer().frame(height: 52)

            // Hero headline
            Text(page.headline)
                .font(.system(size: 44, weight: .bold, design: .default))
                .multilineTextAlignment(.center)
                .foregroundStyle(Design.Colors.primaryText(for: colorScheme))
                .lineSpacing(2)
                .opacity(headlineVisible ? 1 : 0)
                .offset(y: headlineVisible ? 0 : 22)

            Spacer().frame(height: 18)

            // Supporting copy
            Text(page.subheadline)
                .font(.system(size: 17, weight: .regular))
                .multilineTextAlignment(.center)
                .foregroundStyle(Design.Colors.secondaryText(for: colorScheme))
                .lineSpacing(4)
                .opacity(subtitleVisible ? 1 : 0)
                .offset(y: subtitleVisible ? 0 : 14)

            Spacer()
            Spacer() // extra bottom space so content clears the bottom bar
        }
        .padding(.horizontal, 36)
        .onAppear(perform: triggerEntrance)
        .onDisappear(perform: resetState)
    }

    // MARK: Icon

    private var iconView: some View {
        ZStack {
            // Outer soft glow
            Circle()
                .fill(page.accentColor.opacity(0.07))
                .frame(width: 160, height: 160)

            // Inner circle background
            Circle()
                .fill(page.accentColor.opacity(0.13))
                .frame(width: 110, height: 110)

            Image(systemName: page.icon)
                .font(.system(size: 46, weight: .light))
                .foregroundStyle(page.accentColor)
                .symbolEffect(
                    .variableColor.iterative.dimInactiveLayers,
                    isActive: page.animateIcon
                )
        }
    }

    // MARK: Animation

    private func triggerEntrance() {
        withAnimation(.spring(response: 0.65, dampingFraction: 0.72).delay(0.08)) {
            iconVisible = true
        }
        withAnimation(.spring(response: 0.6, dampingFraction: 0.8).delay(0.22)) {
            headlineVisible = true
        }
        withAnimation(.spring(response: 0.6, dampingFraction: 0.8).delay(0.36)) {
            subtitleVisible = true
        }
    }

    private func resetState() {
        iconVisible = false
        headlineVisible = false
        subtitleVisible = false
    }
}

// MARK: - CTA Page

private struct OnboardingCTAPage: View {
    let colorScheme: ColorScheme
    let onError: (String) -> Void

    @State private var iconVisible = false
    @State private var headlineVisible = false
    @State private var subtitleVisible = false
    @State private var ctaVisible = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // Animated app icon
            ZStack {
                Circle()
                    .fill(Design.Colors.primary.opacity(0.07))
                    .frame(width: 160, height: 160)

                Circle()
                    .fill(Design.Colors.primary.opacity(0.13))
                    .frame(width: 110, height: 110)

                Image(systemName: "dot.radiowaves.left.and.right")
                    .font(.system(size: 46, weight: .light))
                    .foregroundStyle(Design.Colors.primary)
                    .symbolEffect(.variableColor.iterative.dimInactiveLayers, isActive: true)
            }
            .scaleEffect(iconVisible ? 1.0 : 0.72)
            .opacity(iconVisible ? 1 : 0)

            Spacer().frame(height: 52)

            Text("Ready to start?")
                .font(.system(size: 44, weight: .bold))
                .foregroundStyle(Design.Colors.primaryText(for: colorScheme))
                .opacity(headlineVisible ? 1 : 0)
                .offset(y: headlineVisible ? 0 : 22)

            Spacer().frame(height: 18)

            Text("Sign in to sync everything across your devices, or jump straight in as a guest.")
                .font(.system(size: 17, weight: .regular))
                .multilineTextAlignment(.center)
                .foregroundStyle(Design.Colors.secondaryText(for: colorScheme))
                .lineSpacing(4)
                .opacity(subtitleVisible ? 1 : 0)
                .offset(y: subtitleVisible ? 0 : 14)

            Spacer().frame(height: 52)

            // Auth buttons
            VStack(spacing: 14) {
                SignInWithAppleButton(.continue, onRequest: configureRequest, onCompletion: handleResult)
                    .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
                    .frame(height: 54)
                    .clipShape(RoundedRectangle(cornerRadius: Design.Radius.standard + 2))
                    .shadow(
                        color: .black.opacity(colorScheme == .dark ? 0.5 : 0.15),
                        radius: 12, x: 0, y: 6
                    )

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
            .opacity(ctaVisible ? 1 : 0)
            .offset(y: ctaVisible ? 0 : 16)

            Spacer()
        }
        .padding(.horizontal, 36)
        .onAppear(perform: triggerEntrance)
        .onDisappear(perform: resetState)
    }

    private func triggerEntrance() {
        withAnimation(.spring(response: 0.65, dampingFraction: 0.72).delay(0.08)) {
            iconVisible = true
        }
        withAnimation(.spring(response: 0.6, dampingFraction: 0.8).delay(0.22)) {
            headlineVisible = true
        }
        withAnimation(.spring(response: 0.6, dampingFraction: 0.8).delay(0.36)) {
            subtitleVisible = true
        }
        withAnimation(.spring(response: 0.6, dampingFraction: 0.8).delay(0.5)) {
            ctaVisible = true
        }
    }

    private func resetState() {
        iconVisible = false
        headlineVisible = false
        subtitleVisible = false
        ctaVisible = false
    }

    private func configureRequest(_ request: ASAuthorizationAppleIDRequest) {
        request.requestedScopes = [.fullName, .email]
    }

    private func handleResult(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let authorization):
            AuthenticationManager.shared.signIn(with: authorization)
        case .failure(let error):
            if let authError = error as? ASAuthorizationError, authError.code == .canceled {
                return
            }
            onError(error.localizedDescription)
        }
    }
}

// MARK: - Bottom Bar (Dots + Next Button)

private struct OnboardingBottomBar: View {
    @Binding var currentPage: Int
    let totalPages: Int

    var body: some View {
        HStack(alignment: .center) {
            // Pill-style page indicator
            HStack(spacing: 7) {
                ForEach(0..<totalPages, id: \.self) { index in
                    Capsule()
                        .fill(dotColor(for: index))
                        .frame(
                            width: index == currentPage ? 26 : 8,
                            height: 8
                        )
                        .animation(
                            .spring(response: 0.4, dampingFraction: 0.75),
                            value: currentPage
                        )
                }
            }

            Spacer()

            // Next arrow button
            Button {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.82)) {
                    currentPage = min(currentPage + 1, totalPages - 1)
                }
            } label: {
                Image(systemName: "arrow.right")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 54, height: 54)
                    .background(Design.Colors.primary)
                    .clipShape(Circle())
                    .shadow(
                        color: Design.Colors.primary.opacity(0.45),
                        radius: 14, x: 0, y: 5
                    )
            }
        }
    }

    private func dotColor(for index: Int) -> Color {
        index == currentPage
            ? Design.Colors.primary
            : Color.gray.opacity(0.35)
    }
}

// MARK: - Preview

#Preview("Light") {
    OnboardingView()
        .preferredColorScheme(.light)
}

#Preview("Dark") {
    OnboardingView()
        .preferredColorScheme(.dark)
}
