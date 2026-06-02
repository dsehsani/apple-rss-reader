//
//  TutorialHeroView.swift
//  Payam
//
//  Full-screen welcome cover shown on first launch. Sets the tone for the
//  tour with a soft Apple-blue gradient, layered SF Symbol stack, and a
//  single primary CTA. Skipping here ends the tour entirely.
//

import SwiftUI

struct TutorialHeroView: View {

    @Environment(\.colorScheme) private var colorScheme

    let onStart: () -> Void
    let onSkip: () -> Void

    @State private var appeared = false
    @State private var iconFloat = false

    var body: some View {
        ZStack {
            // Background — soft radial gradient blending Apple blue into the app's charcoal/cream.
            ZStack {
                Design.Colors.background(for: colorScheme)
                    .ignoresSafeArea()

                RadialGradient(
                    colors: [
                        Design.Colors.primary.opacity(colorScheme == .dark ? 0.32 : 0.18),
                        Design.Colors.primary.opacity(0.0)
                    ],
                    center: .init(x: 0.5, y: 0.3),
                    startRadius: 20,
                    endRadius: 360
                )
                .ignoresSafeArea()
            }

            VStack(spacing: 0) {
                Spacer(minLength: 32)

                heroIllustration
                    .padding(.bottom, 44)

                Text("Your reading,\non your terms.")
                    .font(.system(size: 34, weight: .bold))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Design.Colors.primaryText(for: colorScheme))
                    .lineSpacing(2)
                    .padding(.bottom, 16)

                Text("Payam pulls together blogs, podcasts, YouTube,\nand newsletters — no algorithm picking for you.")
                    .font(.system(size: 16))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Design.Colors.secondaryText(for: colorScheme))
                    .lineSpacing(4)
                    .padding(.horizontal, 32)

                Spacer()

                VStack(spacing: 14) {
                    Button(action: onStart) {
                        Text("Get started")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                            .background(
                                Capsule()
                                    .fill(Design.Colors.primary)
                                    .shadow(color: Design.Colors.primary.opacity(0.45),
                                            radius: 16, y: 6)
                            )
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 24)

                    Button(action: onSkip) {
                        Text("Skip tour")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(Design.Colors.secondaryText(for: colorScheme))
                            .frame(height: 36)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.bottom, 36)
            }
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 8)
        }
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.85)) {
                appeared = true
            }
            iconFloat = true
        }
    }

    // MARK: - Hero illustration: stacked SF Symbols on layered tinted plates

    private var heroIllustration: some View {
        ZStack {
            // Outermost soft plate
            RoundedRectangle(cornerRadius: 44)
                .fill(Design.Colors.primary.opacity(colorScheme == .dark ? 0.12 : 0.08))
                .frame(width: 200, height: 200)

            // Mid plate
            RoundedRectangle(cornerRadius: 36)
                .fill(Design.Colors.primary.opacity(colorScheme == .dark ? 0.18 : 0.12))
                .frame(width: 156, height: 156)

            // Inner gradient tile
            RoundedRectangle(cornerRadius: 28)
                .fill(
                    LinearGradient(
                        colors: [
                            Design.Colors.primary,
                            Design.Colors.primary.opacity(0.7)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 112, height: 112)
                .shadow(color: Design.Colors.primary.opacity(0.4), radius: 14, y: 6)

            Image(systemName: "dot.radiowaves.left.and.right")
                .font(.system(size: 52, weight: .semibold))
                .foregroundStyle(.white)
                .offset(y: iconFloat ? -2 : 2)
                .animation(.easeInOut(duration: 2.8).repeatForever(autoreverses: true), value: iconFloat)
        }
    }
}

#Preview {
    TutorialHeroView(onStart: {}, onSkip: {})
}
