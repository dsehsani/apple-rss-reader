//
//  DiscoverView.swift
//  OpenRSS
//
//  Created by Darius Ehsani on 2/3/26.
//

import SwiftUI

/// Discover view with featured content, trending, and recommended sources
struct DiscoverView: View {

    // MARK: - Environment (Light/Dark Mode)

    @Environment(\.colorScheme) private var colorScheme

    // MARK: - Body

    var body: some View {
        ZStack(alignment: .top) {
            // Background - adaptive for light/dark mode
            Design.Colors.background(for: colorScheme).ignoresSafeArea()

            // Main content — safeAreaInset adapts to any device automatically
            ScrollView {
                VStack(spacing: Design.Spacing.section) {
                    // Featured section
                    featuredSection

                    // Trending section
                    trendingSection

                    // Recommended sources section
                    recommendedSourcesSection
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                headerView
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                Color.clear.frame(height: 94)
            }
        }
    }

    // MARK: - Header View
    // .ignoresSafeArea(edges: .top) lets the material fill up to the Dynamic Island / notch.
    // Content padding uses the safe area automatically via safeAreaInset placement.

    private var headerView: some View {
        Text("Discover")
            .font(Design.Typography.largeTitle)
            .foregroundStyle(Design.Colors.primaryText(for: colorScheme))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Design.Spacing.edge + 4)
            .padding(.top, 16)
            .padding(.bottom, Design.Spacing.edge)
            .background(
                Rectangle()
                    .fill(colorScheme == .dark ? .ultraThinMaterial : .regularMaterial)
                    .overlay(alignment: .bottom) {
                        Rectangle()
                            .fill(Design.Colors.glassBorder(for: colorScheme))
                            .frame(height: 0.5)
                    }
                    .ignoresSafeArea(edges: .top)
            )
    }

    // MARK: - Featured Section

    private var featuredSection: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.edge) {
            sectionHeader(title: "Featured", icon: "star.fill")

            // Featured card (larger)
            VStack(alignment: .leading, spacing: 0) {
                // Hero image placeholder
                ZStack {
                    LinearGradient(
                        colors: [Design.Colors.primary.opacity(0.4), Design.Colors.primary.opacity(0.1)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )

                    Image(systemName: "sparkles")
                        .font(.system(size: 64))
                        .foregroundStyle(.white.opacity(0.3))
                }
                .aspectRatio(16/9, contentMode: .fill)
                .clipped()

                VStack(alignment: .leading, spacing: Design.Spacing.small) {
                    Text("Editor's Pick")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Design.Colors.primary)
                        .textCase(.uppercase)
                        .tracking(1)

                    Text("The Best RSS Feeds to Follow in 2026")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(Design.Colors.primaryText(for: colorScheme))
                        .lineLimit(2)

                    Text("Our curated collection of must-follow sources for staying informed across tech, design, and productivity.")
                        .font(Design.Typography.body)
                        .foregroundStyle(Design.Colors.secondaryText)
                        .lineLimit(3)
                }
                .padding(Design.Spacing.cardPadding)
            }
            .cardStyle()
            .padding(.horizontal, Design.Spacing.edge)
        }
    }

    // MARK: - Trending Section

    private var trendingSection: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.edge) {
            sectionHeader(title: "Trending Now", icon: "flame.fill")

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Design.Spacing.edge) {
                    ForEach(trendingItems, id: \.title) { item in
                        trendingCard(item)
                    }
                }
                .padding(.horizontal, Design.Spacing.edge)
            }
        }
    }

    private func trendingCard(_ item: TrendingItem) -> some View {
        VStack(alignment: .leading, spacing: Design.Spacing.small) {
            // Icon
            ZStack {
                RoundedRectangle(cornerRadius: Design.Radius.small)
                    .fill(item.color.opacity(0.15))
                    .frame(width: 48, height: 48)

                Image(systemName: item.icon)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(item.color)
            }

            Text(item.title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Design.Colors.primaryText(for: colorScheme))
                .lineLimit(2)

            Text(item.subtitle)
                .font(.system(size: 13))
                .foregroundStyle(Design.Colors.secondaryText)
                .lineLimit(1)
        }
        .frame(width: 140)
        .padding(Design.Spacing.cardPadding)
        .background(Design.Colors.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: Design.Radius.standard))
        .overlay(
            RoundedRectangle(cornerRadius: Design.Radius.standard)
                .stroke(Design.Colors.subtleBorder, lineWidth: 1)
        )
    }

    // MARK: - Recommended Sources Section

    private var recommendedSourcesSection: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.edge) {
            sectionHeader(title: "Recommended Sources", icon: "plus.circle.fill")

            VStack(spacing: 1) {
                ForEach(recommendedSources, id: \.name) { source in
                    HStack(spacing: 12) {
                        // Icon
                        ZStack {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(source.color.opacity(0.15))
                                .frame(width: 44, height: 44)

                            Image(systemName: source.icon)
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(source.color)
                        }

                        // Info
                        VStack(alignment: .leading, spacing: 2) {
                            Text(source.name)
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(Design.Colors.primaryText(for: colorScheme))

                            Text(source.description)
                                .font(.system(size: 13))
                                .foregroundStyle(Design.Colors.secondaryText)
                                .lineLimit(1)
                        }

                        Spacer()

                        // Add button
                        Button {
                            // Add source
                        } label: {
                            Image(systemName: "plus")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(Design.Colors.primary)
                                .frame(width: 32, height: 32)
                                .background(Design.Colors.primary.opacity(0.1))
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.vertical, 12)
                    .padding(.horizontal, Design.Spacing.edge)
                    .background(Design.Colors.cardBackground.opacity(0.5))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: Design.Radius.standard))
            .overlay(
                RoundedRectangle(cornerRadius: Design.Radius.standard)
                    .stroke(Design.Colors.subtleBorder, lineWidth: 1)
            )
            .padding(.horizontal, Design.Spacing.edge)
        }
    }

    // MARK: - Helper Views

    private func sectionHeader(title: String, icon: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Design.Colors.primary)

            Text(title)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(Design.Colors.primaryText(for: colorScheme))
        }
        .padding(.horizontal, Design.Spacing.edge)
    }

    // MARK: - Sample Data

    private var trendingItems: [TrendingItem] {
        [
            TrendingItem(title: "AI Tools", subtitle: "42 new articles", icon: "brain.head.profile", color: .purple),
            TrendingItem(title: "SwiftUI", subtitle: "28 new articles", icon: "swift", color: .orange),
            TrendingItem(title: "Remote Work", subtitle: "19 new articles", icon: "house.fill", color: .green),
            TrendingItem(title: "Design Systems", subtitle: "15 new articles", icon: "paintpalette.fill", color: .pink)
        ]
    }

    private var recommendedSources: [RecommendedSource] {
        [
            RecommendedSource(name: "CSS-Tricks", description: "Tips, tricks, and techniques on using CSS", icon: "chevron.left.forwardslash.chevron.right", color: .orange),
            RecommendedSource(name: "A List Apart", description: "Explores the design, development, and meaning of web content", icon: "list.bullet.rectangle", color: .blue),
            RecommendedSource(name: "Daring Fireball", description: "John Gruber's commentary on Apple and tech", icon: "flame.fill", color: .red)
        ]
    }
}

// MARK: - Supporting Types

private struct TrendingItem {
    let title: String
    let subtitle: String
    let icon: String
    let color: Color
}

private struct RecommendedSource {
    let name: String
    let description: String
    let icon: String
    let color: Color
}

// MARK: - Preview

#Preview {
    DiscoverView()
}
