//
//  ClusterCardView.swift
//  OpenRSS
//
//  Phase 2b — SwiftUI view for a clustered story card.
//  Shows the canonical article with a "Covered by N sources" indicator.
//  Tappable to expand and reveal all articles in the cluster.
//

import SwiftUI

// MARK: - ClusterCardView

struct ClusterCardView: View {

    // MARK: - Properties

    let cluster: ClusterCard
    let source: Source?
    var onArticleTap: ((FeedItem) -> Void)?
    /// Resolves a FeedItem to its Source (needed for non-canonical items in the expanded list).
    var sourceForItem: ((FeedItem) -> Source?)?

    // MARK: - State

    @State private var isExpanded = false

    // MARK: - Environment

    @Environment(\.colorScheme) private var colorScheme

    // MARK: - Resolved og:image

    @State private var ogImageURL: String?

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Hero image from canonical item
            heroImage

            // Content
            VStack(alignment: .leading, spacing: Design.Spacing.small) {
                sourceInfoRow
                titleText
                excerptText
                clusterIndicator
            }
            .padding(Design.Spacing.cardPadding)

            // Expanded source list
            if isExpanded {
                expandedSources
            }
        }
        .cardStyle(for: colorScheme)
        .contentShape(Rectangle())
        .onTapGesture {
            onArticleTap?(cluster.canonicalItem)
        }
        .task(id: cluster.canonicalItem.id) {
            guard cluster.canonicalItem.imageURL == nil else { return }
            if let cached = await OGImageService.shared.cachedImageURL(for: cluster.canonicalItem.link.absoluteString) {
                ogImageURL = cached
                return
            }
            await OGImageService.shared.prefetch(articleURL: cluster.canonicalItem.link.absoluteString)
            ogImageURL = await OGImageService.shared.cachedImageURL(for: cluster.canonicalItem.link.absoluteString)
        }
    }

    // MARK: - Subviews

    private var heroImage: some View {
        ZStack {
            placeholderHero

            let displayURL = cluster.canonicalItem.imageURL ?? ogImageURL
            if let urlString = displayURL, let url = URL(string: urlString) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    case .empty:
                        Color.clear
                            .overlay(ProgressView().tint(.white.opacity(0.5)))
                    case .failure:
                        Color.clear
                    @unknown default:
                        Color.clear
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 180)
        .clipped()
    }

    private var placeholderHero: some View {
        ZStack {
            LinearGradient(
                colors: [
                    (source?.iconColor ?? .blue).opacity(colorScheme == .dark ? 0.3 : 0.2),
                    (source?.iconColor ?? .blue).opacity(colorScheme == .dark ? 0.1 : 0.05)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Image(systemName: source?.icon ?? "doc.text.fill")
                .font(.system(size: 48))
                .foregroundStyle(Design.Colors.primaryText(for: colorScheme).opacity(0.3))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var sourceInfoRow: some View {
        HStack(spacing: Design.Spacing.small) {
            ZStack {
                RoundedRectangle(cornerRadius: 4)
                    .fill((source?.iconColor ?? .blue).opacity(0.2))
                    .frame(width: 20, height: 20)

                Image(systemName: source?.icon ?? "globe")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(source?.iconColor ?? .blue)
            }

            Text("\(source?.name ?? "Unknown") \u{2022} \(cluster.canonicalItem.relativeTimeString)")
                .font(Design.Typography.caption)
                .foregroundStyle(Design.Colors.secondaryText)
                .textCase(.uppercase)
                .tracking(0.5)
        }
    }

    private var titleText: some View {
        Text(cluster.canonicalItem.title)
            .font(Design.Typography.cardTitle)
            .foregroundStyle(Design.Colors.primaryText(for: colorScheme))
            .lineLimit(2)
            .tracking(-0.3)
    }

    private var excerptText: some View {
        Text(cluster.canonicalItem.excerpt)
            .font(Design.Typography.body)
            .foregroundStyle(Design.Colors.secondaryText)
            .lineLimit(2)
            .lineSpacing(2)
    }

    private var clusterIndicator: some View {
        Button {
            withAnimation(Design.Animation.standard) {
                isExpanded.toggle()
            }
            // Phase 2d — track cluster expand
            if isExpanded {
                AffinityTracker.shared.record(
                    .clusterExpand,
                    sourceID: cluster.canonicalItem.sourceID,
                    itemID: cluster.canonicalItem.id
                )
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "square.stack.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Design.Colors.primary)

                Text("Covered by \(cluster.sourceCount) sources")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Design.Colors.primary)

                Spacer()

                Image(systemName: isExpanded ? Design.Icons.chevronDown : Design.Icons.chevronRight)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Design.Colors.secondaryText(for: colorScheme))
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
            .background(
                RoundedRectangle(cornerRadius: Design.Radius.small)
                    .fill(Design.Colors.primary.opacity(colorScheme == .dark ? 0.1 : 0.08))
            )
        }
        .buttonStyle(.plain)
        .padding(.top, Design.Spacing.xSmall)
    }

    private var expandedSources: some View {
        VStack(alignment: .leading, spacing: 0) {
            Rectangle()
                .fill(colorScheme == .dark ? Design.Colors.subtleBorder : Color.black.opacity(0.06))
                .frame(height: 1)

            VStack(alignment: .leading, spacing: 2) {
                // Show non-canonical items as tappable article rows
                ForEach(nonCanonicalItems) { item in
                    Button {
                        onArticleTap?(item)
                    } label: {
                        clusterArticleRow(item)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 8)
            .padding(.horizontal, Design.Spacing.cardPadding)
        }
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    /// All cluster items except the canonical one, sorted by recency.
    private var nonCanonicalItems: [FeedItem] {
        cluster.allItems
            .filter { $0.id != cluster.canonicalItem.id }
            .sorted { $0.publishedAt > $1.publishedAt }
    }

    /// A compact article row showing source icon, title, excerpt snippet, and time.
    private func clusterArticleRow(_ item: FeedItem) -> some View {
        HStack(alignment: .top, spacing: 10) {
            // Source icon
            if let itemSource = sourceForItem?(item) {
                ZStack {
                    RoundedRectangle(cornerRadius: 4)
                        .fill((itemSource.iconColor).opacity(0.2))
                        .frame(width: 20, height: 20)
                    Image(systemName: itemSource.icon)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(itemSource.iconColor)
                }
                .padding(.top, 2)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Design.Colors.primaryText(for: colorScheme))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                HStack(spacing: 4) {
                    if let itemSource = sourceForItem?(item) {
                        Text(itemSource.name)
                            .font(.system(size: 11))
                            .foregroundStyle(Design.Colors.secondaryText)
                    }
                    Text("·")
                        .font(.system(size: 11))
                        .foregroundStyle(Design.Colors.secondaryText)
                    Text(item.relativeTimeString)
                        .font(.system(size: 11))
                        .foregroundStyle(Design.Colors.secondaryText)
                }
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Design.Colors.secondaryText.opacity(0.6))
                .padding(.top, 4)
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }
}

// MARK: - FeedItem Relative Time Helper

extension FeedItem {
    /// Relative time string for display (e.g., "2h ago").
    var relativeTimeString: String {
        let interval = Date().timeIntervalSince(publishedAt)
        let minutes = Int(interval / 60)
        let hours = Int(interval / 3600)
        let days = Int(interval / 86400)

        if minutes < 1 { return "Just now" }
        if minutes < 60 { return "\(minutes)m ago" }
        if hours < 24 { return "\(hours)h ago" }
        if days < 7 { return "\(days)d ago" }
        return publishedAt.formatted(.dateTime.month(.abbreviated).day())
    }
}
