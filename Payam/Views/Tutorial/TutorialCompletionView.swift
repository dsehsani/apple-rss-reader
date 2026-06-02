//
//  TutorialCompletionView.swift
//  Payam
//
//  Celebration cover shown once the user finishes all 5 checklist items.
//  Brief confetti burst (CoreGraphics, no third-party deps) then a single
//  CTA that drops them into the Today tab.
//

import SwiftUI

struct TutorialCompletionView: View {

    @Environment(\.colorScheme) private var colorScheme

    let onFinish: () -> Void

    @State private var confettiPieces: [ConfettiPiece] = []
    @State private var appeared = false
    @State private var checkPulse = false

    var body: some View {
        ZStack {
            Design.Colors.background(for: colorScheme).ignoresSafeArea()

            // Confetti layer (behind the card)
            TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { context in
                Canvas { ctx, size in
                    let now = context.date.timeIntervalSinceReferenceDate
                    for piece in confettiPieces {
                        let t = max(0, now - piece.startTime)
                        let x = piece.startX + piece.driftX * t * 60
                        let y = piece.startY + (piece.fallSpeed * t * 200)
                        let rotation = piece.rotation + t * piece.spin
                        let opacity = max(0, 1.0 - (t / piece.lifespan))

                        guard y < size.height + 40 else { continue }

                        let transform = CGAffineTransform.identity
                            .translatedBy(x: x, y: y)
                            .rotated(by: rotation)
                        let rect = CGRect(x: -3, y: -6, width: 6, height: 12)
                        let path = Path(roundedRect: rect, cornerRadius: 1.5)
                            .applying(transform)
                        ctx.fill(path, with: .color(piece.color.opacity(opacity)))
                    }
                }
            }
            .allowsHitTesting(false)

            VStack(spacing: 0) {
                Spacer(minLength: 40)

                // Big check
                ZStack {
                    Circle()
                        .fill(Design.Colors.primary.opacity(0.10))
                        .frame(width: 160, height: 160)
                    Circle()
                        .fill(Design.Colors.primary.opacity(0.18))
                        .frame(width: 116, height: 116)
                    Circle()
                        .fill(Design.Colors.primary)
                        .frame(width: 84, height: 84)
                        .shadow(color: Design.Colors.primary.opacity(0.45), radius: 16, y: 6)
                    Image(systemName: "checkmark")
                        .font(.system(size: 38, weight: .bold))
                        .foregroundStyle(.white)
                        .scaleEffect(checkPulse ? 1.08 : 1.0)
                        .animation(.spring(response: 0.4, dampingFraction: 0.55).repeatCount(2, autoreverses: true),
                                   value: checkPulse)
                }
                .padding(.bottom, 32)

                Text("You're all set.")
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(Design.Colors.primaryText(for: colorScheme))
                    .padding(.bottom, 14)

                Text("Add more sources anytime in Discover, or paste any RSS URL into Add Feed. Replay this tour from Settings.")
                    .font(.system(size: 15))
                    .foregroundStyle(Design.Colors.secondaryText(for: colorScheme))
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .padding(.horizontal, 36)

                Spacer()

                Button(action: onFinish) {
                    Text("Start reading")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(
                            Capsule()
                                .fill(Design.Colors.primary)
                                .shadow(color: Design.Colors.primary.opacity(0.45), radius: 16, y: 6)
                        )
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 24)
                .padding(.bottom, 40)
            }
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 10)
        }
        .onAppear {
            withAnimation(.spring(response: 0.55, dampingFraction: 0.85)) {
                appeared = true
            }
            checkPulse = true
            launchConfetti()
        }
    }

    // MARK: - Confetti

    private func launchConfetti() {
        let colors: [Color] = [
            Design.Colors.primary,
            .pink, .orange, .yellow, .green, .purple, .cyan
        ]
        let now = Date().timeIntervalSinceReferenceDate
        var pieces: [ConfettiPiece] = []
        for _ in 0..<80 {
            pieces.append(
                ConfettiPiece(
                    startX: CGFloat.random(in: 60...340),
                    startY: -20,
                    driftX: CGFloat.random(in: -0.6...0.6),
                    fallSpeed: CGFloat.random(in: 1.4...2.6),
                    rotation: CGFloat.random(in: 0...(.pi * 2)),
                    spin: CGFloat.random(in: -3...3),
                    color: colors.randomElement() ?? Design.Colors.primary,
                    startTime: now + Double.random(in: 0...0.5),
                    lifespan: Double.random(in: 1.8...2.8)
                )
            )
        }
        confettiPieces = pieces

        // Clear after animation finishes
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.2) {
            confettiPieces = []
        }
    }
}

// MARK: - Confetti piece

private struct ConfettiPiece: Identifiable {
    let id = UUID()
    let startX: CGFloat
    let startY: CGFloat
    let driftX: CGFloat
    let fallSpeed: CGFloat
    let rotation: CGFloat
    let spin: CGFloat
    let color: Color
    let startTime: TimeInterval
    let lifespan: Double
}

#Preview {
    TutorialCompletionView(onFinish: {})
}
