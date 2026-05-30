//
//  TutorialOverlayView.swift
//  Payam
//
//  Three visual modes:
//
//  1. Full-screen  (whatIsRSS, done)
//     Dark scrim + centered modal card. Blocks all interaction.
//
//  2. Spotlight  (todayFeed, sources)
//     Dark scrim with a transparent cutout over the tagged UI element,
//     plus a fixed bottom info card with Next / Skip buttons.
//     Cutout uses an even-odd Path fill instead of blendMode to prevent
//     rendering corruption during step transitions.
//
//  3. Interactive  (createFolder, addFromDiscover, deleteFolder)
//     NO scrim — the underlying app is fully live and tappable.
//     A floating instruction card sits at the bottom with only a Skip button.
//     SwiftData observable properties are read in body so the view auto-advances
//     when the user actually performs the required action.
//

import SwiftUI

// MARK: - Spotlight cutout shape (even-odd fill, no blendMode)

private struct SpotlightMask: Shape {
    var spotlightRect: CGRect
    var cornerRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path(rect)
        path.addPath(Path(roundedRect: spotlightRect, cornerRadius: cornerRadius))
        return path
    }
}

// MARK: - TutorialOverlayView

struct TutorialOverlayView: View {

    @Environment(\.colorScheme) private var colorScheme

    let step: TutorialStep
    let spotlightFrame: CGRect?
    let screenSize: CGSize
    let onNext: () -> Void
    let onSkip: () -> Void

    private let spotlightPadding: CGFloat = 16
    private let cardBottomInset: CGFloat = 110

    var body: some View {
        ZStack(alignment: .bottom) {
            // Forces ZStack to always fill the full screen so that .bottom
            // alignment correctly anchors the card, even when scrimContent
            // returns EmptyView (interactive steps with no scrim).
            Color.clear
                .ignoresSafeArea()
                .allowsHitTesting(false)

            scrimContent

            cardContent
                .id(step)
        }
        .ignoresSafeArea()
        .animation(.spring(response: 0.38, dampingFraction: 0.82), value: step)
    }

    // MARK: - Scrim layer (always a single child in the ZStack)

    @ViewBuilder
    private var scrimContent: some View {
        if step.isFullScreen {
            Color.black.opacity(0.82)
                .ignoresSafeArea()
        } else if !step.isInteractive {
            scrimWithCutout
        }
        // Interactive: no scrim — app is fully live
    }

    // MARK: - Card layer (always a single child in the ZStack)

    @ViewBuilder
    private var cardContent: some View {
        if step.isFullScreen {
            fullScreenCard
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .scale(scale: 0.95)),
                    removal: .opacity
                ))
        } else if step.isInteractive {
            interactiveCard
                .padding(.horizontal, 16)
                .padding(.bottom, cardBottomInset)
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .move(edge: .bottom)),
                    removal: .opacity
                ))
        } else {
            bottomInfoCard
                .padding(.horizontal, 16)
                .padding(.bottom, cardBottomInset)
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .move(edge: .bottom)),
                    removal: .opacity
                ))
        }
    }

    // MARK: - Mode 1: Full-Screen Card

    private var fullScreenCard: some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(spacing: 28) {
                // Icon ring
                ZStack {
                    Circle().fill(Design.Colors.primary.opacity(0.14)).frame(width: 100, height: 100)
                    Circle().fill(Design.Colors.primary.opacity(0.22)).frame(width: 72, height: 72)
                    Image(systemName: step.icon)
                        .font(.system(size: 32, weight: .light))
                        .foregroundStyle(Design.Colors.primary)
                }

                // Text
                VStack(spacing: 14) {
                    Text(step.title)
                        .font(.system(size: 30, weight: .bold))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)

                    Text(step.body)
                        .font(.system(size: 16))
                        .foregroundStyle(.white.opacity(0.90))
                        .multilineTextAlignment(.center)
                        .lineSpacing(5)
                        .fixedSize(horizontal: false, vertical: true)
                }

                // Buttons
                VStack(spacing: 10) {
                    Button(action: onNext) {
                        Text(step == .done ? "Get Started" : "Take the Tour  →")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity).frame(height: 54)
                            .background(Design.Colors.primary)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    if step != .done {
                        Button(action: onSkip) {
                            Text("Skip tutorial")
                                .font(.system(size: 15))
                                .foregroundStyle(.white.opacity(0.65))
                                .frame(maxWidth: .infinity).frame(height: 44)
                        }
                    }
                }
            }
            .padding(28)
            .frame(maxWidth: 380)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Mode 2: Scrim + Spotlight Cutout (Path-based even-odd fill)

    @ViewBuilder
    private var scrimWithCutout: some View {
        if step.hasSpotlight, let f = spotlightFrame {
            let expanded = f.insetBy(dx: -spotlightPadding, dy: -spotlightPadding)
            SpotlightMask(spotlightRect: expanded, cornerRadius: 20)
                .fill(Color.black.opacity(0.70), style: FillStyle(eoFill: true))
                .ignoresSafeArea()
        } else {
            Color.black.opacity(0.70)
                .ignoresSafeArea()
        }
    }

    // MARK: - Mode 2: Bottom Info Card (spotlight steps)

    private var bottomInfoCard: some View {
        VStack(spacing: 0) {
            if step.hasSpotlight && spotlightFrame != nil {
                Image(systemName: "arrowtriangle.up.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.55))
                    .padding(.bottom, 6)
            }
            VStack(alignment: .leading, spacing: 16) {
                // Title row + counter
                HStack(spacing: 10) {
                    Image(systemName: step.icon)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Design.Colors.primary)
                    Text(step.title)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                    Spacer()
                    Text("\(step.stepIndex) of \(TutorialStep.stepCount)")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.80))
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(Color.white.opacity(0.18))
                        .clipShape(Capsule())
                }

                Text(step.body)
                    .font(.system(size: 15))
                    .foregroundStyle(.white)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)

                stepDots

                Divider().background(Color.white.opacity(0.25))

                HStack(spacing: 12) {
                    Button(action: onSkip) {
                        Text("Skip")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(.white.opacity(0.80))
                            .frame(maxWidth: .infinity).frame(height: 44)
                            .background(Color.white.opacity(0.18))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    Button(action: onNext) {
                        HStack(spacing: 6) {
                            Text("Next")
                            Image(systemName: "arrow.right")
                        }
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity).frame(height: 44)
                        .background(Design.Colors.primary)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                }
            }
            .padding(20)
            .background(cardBackground)
            .shadow(color: .black.opacity(0.65), radius: 32, y: 12)
        }
    }

    // MARK: - Mode 3: Interactive Floating Card

    private var interactiveCard: some View {
        VStack(alignment: .leading, spacing: 0) {

            // "App is live" badge row
            HStack(spacing: 6) {
                Circle()
                    .fill(Color.green)
                    .frame(width: 8, height: 8)
                    .overlay(Circle().stroke(Color.green.opacity(0.35), lineWidth: 4))
                Text("App is live — go ahead and try it")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.green)
                Spacer()
                Text("\(step.stepIndex) of \(TutorialStep.stepCount)")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.80))
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(Color.white.opacity(0.18))
                    .clipShape(Capsule())
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 12)

            Divider().background(Color.white.opacity(0.15)).padding(.horizontal, 20)

            // Scrollable body so content never overflows on small screens
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {

                    // Icon + title
                    HStack(spacing: 10) {
                        Image(systemName: step.icon)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Design.Colors.primary)
                        Text(step.title)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                    }

                    // Numbered paragraphs
                    interactiveInstructions

                    stepDots

                    Divider().background(Color.white.opacity(0.25))

                    // Buttons — skip only for most steps; finish option for the last one
                    interactiveButtons
                }
                .padding(.horizontal, 20)
                .padding(.top, 14)
                .padding(.bottom, 20)
            }
            .frame(maxHeight: screenSize.height * 0.42)
        }
        .background(cardBackground)
        .shadow(color: .black.opacity(0.70), radius: 36, y: 14)
    }

    /// Numbered step instructions split on paragraph breaks.
    private var interactiveInstructions: some View {
        let paragraphs = step.body.components(separatedBy: "\n\n")
        return VStack(alignment: .leading, spacing: 10) {
            if paragraphs.indices.contains(0) {
                instructionRow(index: 1, text: paragraphs[0])
            }
            if paragraphs.indices.contains(1) {
                instructionRow(index: 2, text: paragraphs[1])
            }
            if paragraphs.indices.contains(2) {
                instructionRow(index: 3, text: paragraphs[2])
            }
        }
    }

    private func instructionRow(index: Int, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(index)")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Design.Colors.primary)
                .frame(width: 20, height: 20)
                .background(Design.Colors.primary.opacity(0.15))
                .clipShape(Circle())
            Text(text)
                .font(.system(size: 14))
                .foregroundStyle(.white)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var interactiveButtons: some View {
        if step == .deleteFolder {
            // Optional final interactive step — auto-advances on deletion,
            // or user can tap Finish to keep the folder and end the tour.
            VStack(spacing: 10) {
                Button(action: onNext) {
                    Text("Keep My Folder — Finish Tour")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity).frame(height: 44)
                        .background(Design.Colors.primary)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                Button(action: onSkip) {
                    Text("End Tour Early")
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.50))
                        .frame(maxWidth: .infinity).frame(height: 36)
                }
            }
        } else {
            Button(action: onSkip) {
                Text("Skip Tour")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.white.opacity(0.75))
                    .frame(maxWidth: .infinity).frame(height: 44)
                    .background(Color.white.opacity(0.14))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
    }

    // MARK: - Shared Subviews

    private var stepDots: some View {
        HStack(spacing: 6) {
            ForEach(TutorialStep.allCases.filter { !$0.isFullScreen }, id: \.self) { s in
                Capsule()
                    .fill(s == step ? Design.Colors.primary : Color.white.opacity(0.40))
                    .frame(width: s == step ? 20 : 7, height: 7)
                    .animation(.spring(response: 0.35, dampingFraction: 0.8), value: step)
            }
        }
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 20)
            .fill(.ultraThinMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color.black.opacity(0.65))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(Color.white.opacity(0.22), lineWidth: 0.5)
            )
    }
}
