//
//  ShimmerView.swift
//  OpenRSS
//
//  Lightweight skeleton shimmer for image placeholders.
//  A diagonal gradient slides across the view forever to signal "loading"
//  without the visual heaviness of a spinner over the placeholder hero.
//

import SwiftUI

struct ShimmerView: View {

    let cornerRadius: CGFloat
    var baseOpacity: Double = 0.0

    @State private var phase: CGFloat = -1.0

    var body: some View {
        GeometryReader { geo in
            let highlight = LinearGradient(
                colors: [
                    Color.white.opacity(0.0),
                    Color.white.opacity(0.18),
                    Color.white.opacity(0.0)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            highlight
                .frame(width: geo.size.width * 0.6)
                .offset(x: phase * geo.size.width)
                .blendMode(.plusLighter)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
                .onAppear {
                    withAnimation(
                        .linear(duration: 1.4).repeatForever(autoreverses: false)
                    ) {
                        phase = 1.5
                    }
                }
        }
        .background(Color.white.opacity(baseOpacity))
        .allowsHitTesting(false)
    }
}
