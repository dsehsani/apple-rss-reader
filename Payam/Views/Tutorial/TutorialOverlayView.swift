//
//  TutorialOverlayView.swift
//  Payam
//
//  Soft attention glow drawn at the global overlay layer for tutorial steps.
//  Replaces the older heavier pulse ring (1.0 → 1.35 scale every 3.5s) with a
//  calmer breathing halo that fades on user interaction.
//

import SwiftUI

// MARK: - TutorialGlow

/// Soft Apple-blue halo that breathes gently around the target element.
/// Rendered by MainTabView's overlay layer so it isn't clipped by ancestors.
struct TutorialGlow: View {

    @State private var breathing = false

    var body: some View {
        ZStack {
            // Outer soft halo
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Design.Colors.primary.opacity(0.55),
                            Design.Colors.primary.opacity(0.0)
                        ],
                        center: .center,
                        startRadius: 4,
                        endRadius: 60
                    )
                )
                .blur(radius: 8)

            // Inner ring
            Circle()
                .stroke(Design.Colors.primary.opacity(0.55), lineWidth: 2)
                .blur(radius: 0.5)
        }
        .scaleEffect(breathing ? 1.05 : 0.95)
        .opacity(breathing ? 0.55 : 0.90)
        .animation(
            .easeInOut(duration: 2.4).repeatForever(autoreverses: true),
            value: breathing
        )
        .onAppear { breathing = true }
    }
}
