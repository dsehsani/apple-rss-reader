//
//  DiscoverView.swift
//  OpenRSS
//
//  Discover tab with three sections:
//    • Featured    — curated top feeds, each with a + button.
//    • Categories  — horizontal category cards; tap to browse feeds.
//    • Recommended — affinity-weighted feeds the user hasn't subscribed to yet.
//
//  Tapping + on any feed opens QuickAddFeedSheet (folder picker, then subscribe).
//  Tapping a category card opens CategoryFeedsView (full list for that category).
//

import SwiftUI

// MARK: - DiscoverView

struct DiscoverView: View {

    // MARK: - Environment

    @Environment(\.colorScheme) private var colorScheme

    // MARK: - Sheet State

    @State private var feedToAdd: CatalogFeed?        = nil
    @State private var selectedCategory: CatalogCategory? = nil

    // MARK: - Subscribed URLs (observed via SwiftDataService)

    private var subscribedURLs: Set<String> {
        Set(SwiftDataService.shared.sources.map { $0.feedURL.lowercased() })
    }

    private var recommendedFeeds: [CatalogFeed] {
        RSSCatalog.recommendedFeeds(subscribedURLs: subscribedURLs)
    }

    // MARK: - Body

    var body: some View {
        if #available(iOS 26.0, *) {
            liquidGlassBody
        } else {
            legacyBody
        }
    }

    // MARK: - iOS 26+ Liquid Glass Navigation Bar

    @available(iOS 26.0, *)
    private var liquidGlassBody: some View {
        NavigationStack {
            ScrollView {
                contentStack
            }
            .background(Design.Colors.background(for: colorScheme))
            .navigationTitle("Discover")
        }
        .sheet(item: $feedToAdd) { feed in
            QuickAddFeedSheet(feed: feed)
        }
        .sheet(item: $selectedCategory) { cat in
            CategoryFeedsView(category: cat)
        }
    }

    // MARK: - Legacy Body (iOS 17–25)

    private var legacyBody: some View {
        ZStack(alignment: .top) {
            Design.Colors.background(for: colorScheme).ignoresSafeArea()

            ScrollView {
                contentStack
            }
            .safeAreaInset(edge: .top, spacing: 0) { legacyHeaderView }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                Color.clear.frame(height: 94)
            }
        }
        .sheet(item: $feedToAdd) { feed in
            QuickAddFeedSheet(feed: feed)
        }
        .sheet(item: $selectedCategory) { cat in
            CategoryFeedsView(category: cat)
        }
    }

    // MARK: - Legacy Header View

    private var legacyHeaderView: some View {
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

    // MARK: - Content Stack

    private var contentStack: some View {
        VStack(spacing: Design.Spacing.section) {
            featuredSection
            categoriesSection
            recommendedSourcesSection
        }
        .padding(.top, Design.Spacing.edge)
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - Featured Section
    // ─────────────────────────────────────────────────────────────────────────

    private var featuredSection: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.edge) {
            sectionHeader(title: "Featured", icon: "star.fill")

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Design.Spacing.edge) {
                    ForEach(Array(RSSCatalog.featuredFeeds.enumerated()), id: \.offset) { index, feed in
                        featuredCard(feed, gradientIndex: index)
                    }
                }
                .padding(.horizontal, Design.Spacing.edge)
            }
        }
    }

    private func featuredCard(_ feed: CatalogFeed, gradientIndex: Int) -> some View {
        let isSubscribed = subscribedURLs.contains(feed.feedURL.lowercased())
        let gradient     = RSSCatalog.featuredGradients[gradientIndex % RSSCatalog.featuredGradients.count]

        return VStack(alignment: .leading, spacing: 0) {

            // Hero gradient area
            ZStack(alignment: .bottomLeading) {
                LinearGradient(
                    colors: gradient,
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                // Frosted bottom bar with feed name
                VStack(alignment: .leading, spacing: 2) {
                    Text("Editor's Pick")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.8))
                        .textCase(.uppercase)
                        .tracking(1.2)

                    Text(feed.name)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.ultraThinMaterial.opacity(0.6))
            }
            .frame(height: 130)
            .clipped()

            // Description + add button
            VStack(alignment: .leading, spacing: 8) {
                Text(feed.description)
                    .font(.system(size: 13))
                    .foregroundStyle(Design.Colors.secondaryText(for: colorScheme))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                HStack {
                    Spacer()
                    addButton(for: feed, isSubscribed: isSubscribed, compact: false)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
        }
        .frame(width: 260)
        .background(Design.Colors.cardBackground(for: colorScheme))
        .clipShape(RoundedRectangle(cornerRadius: Design.Radius.standard))
        .overlay(
            RoundedRectangle(cornerRadius: Design.Radius.standard)
                .stroke(Design.Colors.subtleBorder, lineWidth: 1)
        )
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - Categories Section
    // ─────────────────────────────────────────────────────────────────────────

    private var categoriesSection: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.edge) {
            sectionHeader(title: "Categories", icon: "square.grid.2x2.fill")

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Design.Spacing.edge) {
                    ForEach(RSSCatalog.categories) { cat in
                        categoryCard(cat)
                    }
                }
                .padding(.horizontal, Design.Spacing.edge)
            }
        }
    }

    private func categoryCard(_ cat: CatalogCategory) -> some View {
        Button {
            selectedCategory = cat
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                // Category icon chip
                ZStack {
                    RoundedRectangle(cornerRadius: Design.Radius.small)
                        .fill(cat.color.opacity(0.15))
                        .frame(width: 46, height: 46)

                    Image(systemName: cat.icon)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(cat.color)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(cat.name)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Design.Colors.primaryText(for: colorScheme))
                        .lineLimit(1)

                    Text("\(cat.feeds.count) sources")
                        .font(.system(size: 11))
                        .foregroundStyle(Design.Colors.secondaryText(for: colorScheme))
                }
            }
            .frame(width: 120)
            .padding(.vertical, 14)
            .padding(.horizontal, 12)
            .background(Design.Colors.cardBackground(for: colorScheme))
            .clipShape(RoundedRectangle(cornerRadius: Design.Radius.standard))
            .overlay(
                RoundedRectangle(cornerRadius: Design.Radius.standard)
                    .stroke(Design.Colors.subtleBorder, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - Recommended Sources Section
    // ─────────────────────────────────────────────────────────────────────────

    private var recommendedSourcesSection: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.edge) {
            sectionHeader(title: "Recommended Sources", icon: "plus.circle.fill")

            if recommendedFeeds.isEmpty {
                Text("You're all caught up! Browse categories above to find more feeds.")
                    .font(.system(size: 14))
                    .foregroundStyle(Design.Colors.secondaryText(for: colorScheme))
                    .multilineTextAlignment(.center)
                    .padding(.vertical, 24)
                    .padding(.horizontal, Design.Spacing.edge)
                    .frame(maxWidth: .infinity)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(recommendedFeeds.enumerated()), id: \.element.id) { index, feed in
                        if index > 0 {
                            Divider()
                                .background(Design.Colors.glassBorder(for: colorScheme))
                                .padding(.leading, Design.Spacing.edge + 56)
                        }
                        recommendedRow(feed)
                    }
                }
                .background(Design.Colors.cardBackground(for: colorScheme).opacity(0.6))
                .clipShape(RoundedRectangle(cornerRadius: Design.Radius.standard))
                .overlay(
                    RoundedRectangle(cornerRadius: Design.Radius.standard)
                        .stroke(Design.Colors.subtleBorder, lineWidth: 1)
                )
                .padding(.horizontal, Design.Spacing.edge)
            }
        }
        .padding(.bottom, Design.Spacing.edge)
    }

    private func recommendedRow(_ feed: CatalogFeed) -> some View {
        let isSubscribed = subscribedURLs.contains(feed.feedURL.lowercased())
        let cat          = RSSCatalog.category(for: feed)

        return HStack(spacing: 12) {
            // Category icon chip
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill((cat?.color ?? Design.Colors.primary).opacity(0.12))
                    .frame(width: 44, height: 44)

                Image(systemName: cat?.icon ?? "dot.radiowaves.left.and.right")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(cat?.color ?? Design.Colors.primary)
            }

            // Feed info
            VStack(alignment: .leading, spacing: 2) {
                Text(feed.name)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Design.Colors.primaryText(for: colorScheme))

                Text(feed.description)
                    .font(.system(size: 12))
                    .foregroundStyle(Design.Colors.secondaryText(for: colorScheme))
                    .lineLimit(1)
            }

            Spacer()

            addButton(for: feed, isSubscribed: isSubscribed, compact: true)
        }
        .padding(.vertical, 11)
        .padding(.horizontal, Design.Spacing.edge)
        .contentShape(Rectangle())
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - Shared Helpers
    // ─────────────────────────────────────────────────────────────────────────

    /// Reusable + / ✓ button for both Featured cards and Recommended rows.
    @ViewBuilder
    private func addButton(for feed: CatalogFeed, isSubscribed: Bool, compact: Bool) -> some View {
        if isSubscribed {
            if compact {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(.green)
            } else {
                Label("Added", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.green)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.green.opacity(0.1))
                    .clipShape(Capsule())
            }
        } else {
            if compact {
                Button {
                    feedToAdd = feed
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Design.Colors.primary)
                        .frame(width: 30, height: 30)
                        .background(Design.Colors.primary.opacity(0.12))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            } else {
                Button {
                    feedToAdd = feed
                } label: {
                    Label("Add Feed", systemImage: "plus")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Design.Colors.primary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Design.Colors.primary.opacity(0.12))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }

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
}

// MARK: - CatalogCategory: Identifiable for sheet(item:)

// CatalogCategory already conforms to Identifiable via its `id: String` computed property,
// so sheet(item: $selectedCategory) works without any additional conformance.

// MARK: - Preview

#Preview {
    DiscoverView()
}
