//
//  SplashGate.swift
//  Payam
//
//  Holds the app's resolved root view (Onboarding / MainTabView) behind an
//  animated splash that runs initial auth + feed refresh in the background.
//  Prevents the "no feeds available → feeds appear" flash on cold launch.
//

import SwiftUI
import Combine

// MARK: - Splash Gate

struct SplashGate<RootContent: View>: View {
    @ViewBuilder var resolvedRoot: () -> RootContent

    @State private var phase: Phase = .splashing
    @State private var progress: Double = 0       // 0 = logo centered, 1 = logo+wordmark layout
    @State private var wordmarkOpacity: Double = 0

    private enum Phase { case splashing, ready }

    var body: some View {
        Group {
            if phase == .splashing {
                SplashCanvas(progress: progress, wordmarkOpacity: wordmarkOpacity)
                    .transition(.opacity)
            } else {
                resolvedRoot()
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: phase)
        .task {
            async let animation: Void = playAnimationTimeline()
            async let loading: Void = runLoadingWithTimeout()
            _ = await (animation, loading)
            phase = .ready
        }
    }

    // MARK: Animation timeline

    private func playAnimationTimeline() async {
        // Brief hold on the centered logo.
        try? await Task.sleep(nanoseconds: 150_000_000)

        // Expand progress 0→1 over 750ms (easeOutCubic).
        withAnimation(.timingCurve(0.215, 0.61, 0.355, 1.0, duration: 0.75)) {
            progress = 1.0
        }

        // 200ms after expansion begins, fade in the wordmark over 500ms.
        try? await Task.sleep(nanoseconds: 200_000_000)
        withAnimation(.easeInOut(duration: 0.5)) {
            wordmarkOpacity = 1.0
        }

        // Wait for the remainder of the expansion (750 - 200 = 550ms). Wordmark fade
        // finishes at 200 + 500 = 700ms after expansion start, so the expansion (750ms)
        // is the longer animation that gates "animation done".
        try? await Task.sleep(nanoseconds: 550_000_000)
    }

    // MARK: Loading with timeout

    private func runLoadingWithTimeout() async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask { @MainActor in
                await Self.runLoading()
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: 6_000_000_000)
            }
            _ = await group.next()
            group.cancelAll()
        }
    }

    @MainActor
    private static func runLoading() async {
        await AuthenticationManager.shared.checkExistingCredential()

        let auth = AuthenticationManager.shared
        let willMountMainApp: Bool
        switch auth.state {
        case .signedIn:
            willMountMainApp = true
        case .signedOut:
            willMountMainApp = !auth.shouldShowOnboarding
        case .unknown:
            willMountMainApp = false
        }
        guard willMountMainApp else { return }

        // Transient orchestrator: drives RiverPipeline.shared.runCycle, populating
        // snapshotPublisher and stamping UserDefaults[lastRefreshKey]. When TodayView
        // mounts later it subscribes to the same publisher and skips its own refresh.
        let prefetchVM = RiverViewModel()
        await prefetchVM.refresh()
    }
}

// MARK: - Splash Canvas
//
// Mirrors the SplashScreen.md reference exactly: a 1024-tall world whose
// visible width animates from 1031 (logo-only) to 2239 (logo + wordmark),
// aspect-fit with the equivalent of preserveAspectRatio="xMidYMid meet".
// The two SVG assets are content-shifted exports of the reference paths, so
// they're placed back at the offsets that restore the original world layout.

private struct SplashCanvas: View {
    let progress: Double
    let wordmarkOpacity: Double

    static let splashBlue = Color(red: 0x27 / 255.0, green: 0x88 / 255.0, blue: 0xFF / 255.0)

    // World coordinate system from SplashScreen.md.
    private static let worldHeight:     CGFloat = 1024
    private static let worldWidthStart: CGFloat = 1031
    private static let worldWidthEnd:   CGFloat = 2239

    // Asset placements in world coords. Logo SVG was exported with paths shifted
    // by (-255, -213); wordmark SVG by (-874.222, -368.573). Placing them back
    // at those origins restores the reference composition.
    private static let logoOrigin     = CGPoint(x: 255,     y: 213)
    private static let logoSize       = CGSize(width: 522,  height: 599)
    private static let wordmarkOrigin = CGPoint(x: 874.222, y: 368.573)
    private static let wordmarkSize   = CGSize(width: 1101, height: 360)

    var body: some View {
        GeometryReader { geo in
            let worldWidth = Self.worldWidthStart
                + (Self.worldWidthEnd - Self.worldWidthStart) * progress

            // Aspect-fit (matches SVG preserveAspectRatio="xMidYMid meet").
            let worldAspect  = worldWidth / Self.worldHeight
            let screenAspect = geo.size.width / max(geo.size.height, 1)
            let fitToWidth   = worldAspect > screenAspect
            let displayedW: CGFloat = fitToWidth ? geo.size.width  : geo.size.height * worldAspect
            let displayedH: CGFloat = fitToWidth ? geo.size.width / worldAspect : geo.size.height
            let scale   = displayedW / worldWidth
            let originX = (geo.size.width  - displayedW) / 2
            let originY = (geo.size.height - displayedH) / 2

            ZStack(alignment: .topLeading) {
                Image("PayamLogo")
                    .resizable()
                    .frame(width: Self.logoSize.width * scale,
                           height: Self.logoSize.height * scale)
                    .offset(x: Self.logoOrigin.x * scale,
                            y: Self.logoOrigin.y * scale)

                Image("PayamWordmark")
                    .resizable()
                    .frame(width: Self.wordmarkSize.width * scale,
                           height: Self.wordmarkSize.height * scale)
                    .offset(x: Self.wordmarkOrigin.x * scale,
                            y: Self.wordmarkOrigin.y * scale)
                    .opacity(wordmarkOpacity)
            }
            .offset(x: originX, y: originY)
        }
        .background(Self.splashBlue.ignoresSafeArea())
        .ignoresSafeArea()
    }
}
