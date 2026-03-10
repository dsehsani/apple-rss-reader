//
//  ArticleSkeletonView.swift
//  OpenRSS
//
//  Priority 5 — Skeleton loading placeholder for the article reader.
//  Shown immediately when the user taps an article, so they see activity
//  within ~0.1s instead of staring at a blank screen for ~3-6s.
//

import SwiftUI

struct ArticleSkeletonView: View {

    @State private var shimmerPhase: CGFloat = -1.0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {

                // Hero image placeholder
                Rectangle()
                    .fill(Color(.secondarySystemFill))
                    .frame(height: 220)
                    .shimmer(phase: shimmerPhase)

                VStack(alignment: .leading, spacing: 8) {
                    // Feed name
                    skeletonBar(widthFraction: 0.25, height: 12)

                    // Title — two lines
                    skeletonBar(widthFraction: 0.85, height: 22)
                    skeletonBar(widthFraction: 0.6, height: 22)

                    // Byline
                    skeletonBar(widthFraction: 0.4, height: 14)
                        .padding(.top, 4)
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 24)

                // Body paragraphs
                VStack(alignment: .leading, spacing: 24) {
                    ForEach(0..<5, id: \.self) { _ in
                        VStack(alignment: .leading, spacing: 8) {
                            skeletonBar(widthFraction: 1.0, height: 14)
                            skeletonBar(widthFraction: 1.0, height: 14)
                            skeletonBar(widthFraction: 0.75, height: 14)
                        }
                    }
                }
                .padding(.horizontal, 20)

                Spacer()
            }
        }
        .background(Color(.systemBackground))
        .onAppear {
            withAnimation(
                .linear(duration: 1.5)
                .repeatForever(autoreverses: false)
            ) {
                shimmerPhase = 1.0
            }
        }
    }

    @ViewBuilder
    private func skeletonBar(widthFraction: CGFloat, height: CGFloat) -> some View {
        GeometryReader { geo in
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(.secondarySystemFill))
                .frame(width: geo.size.width * widthFraction, height: height)
                .shimmer(phase: shimmerPhase)
        }
        .frame(height: height)
    }
}

// MARK: - Shimmer Effect

private struct ShimmerModifier: ViewModifier {
    let phase: CGFloat

    func body(content: Content) -> some View {
        content
            .overlay(
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .white.opacity(0.25), location: 0.5),
                        .init(color: .clear, location: 1)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .offset(x: phase * 300)
            )
            .clipped()
    }
}

private extension View {
    func shimmer(phase: CGFloat) -> some View {
        modifier(ShimmerModifier(phase: phase))
    }
}
