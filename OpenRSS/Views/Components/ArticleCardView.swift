//
//  ArticleCardView.swift
//  OpenRSS
//
//  Created by Darius Ehsani on 2/3/26.
//

import SwiftUI

// MARK: - ClusterBadge

/// Small value type describing a cluster badge shown on an article card.
struct ClusterBadge {
    struct Sibling: Identifiable {
        let article: Article
        let sourceName: String
        var id: UUID { article.id }
    }

    enum Style {
        case sources    // cross-source dedup → "N sources"
        case updates    // same-source burst → "N updates"
        case clustered  // non-canonical shown in source feed view → "Clustered"
    }

    let label: String
    let style: Style
    var siblings: [Sibling] = []
    var onSiblingTap: ((Article) -> Void)? = nil
}

/// Article card component matching the liquid glass design from the schematic
struct ArticleCardView: View {

    // MARK: - Properties

    let article: Article
    let source: Source?
    var decayScore: Double = 1.0
    var clusterBadge: ClusterBadge? = nil
    var onBookmarkTap: (() -> Void)?
    var onReadMoreTap: (() -> Void)?
    var onSplitCluster: (() -> Void)? = nil

    // MARK: - Environment

    @Environment(\.colorScheme) private var colorScheme
    @Environment(AppState.self)  private var appState

    // MARK: - State

    /// Resolved og:image URL for articles whose RSS feed provided no image.
    @State private var ogImageURL: String?

    /// Whether the hero image loaded successfully, hiding the placeholder.
    @State private var heroImageLoaded: Bool = false

    /// Whether the expandable cluster chip is showing its sibling list.
    @State private var isClusterExpanded: Bool = false

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Hero image — hidden when the user has turned off article images
            if appState.showImages {
                heroImage
            }

            // Content
            VStack(alignment: .leading, spacing: Design.Spacing.small) {
                sourceInfoRow
                if let badge = clusterBadge {
                    clusterBadgeChip(badge)
                }
                titleText
                // Excerpt only shown alongside images; compact mode is title-only
                if appState.showImages {
                    excerptText
                }
                if let badge = clusterBadge,
                   isClusterExpanded,
                   !badge.siblings.isEmpty {
                    clusterSiblingList(badge)
                }
                if isPaywalled { paywallBadge }
                footerRow
            }
            .padding(Design.Spacing.cardPadding)
        }
        .cardStyle(for: colorScheme)
        .overlay(alignment: .leading) {
            if clusterBadge?.style == .updates {
                Rectangle()
                    .fill(source?.iconColor ?? Design.Colors.primary)
                    .frame(width: 3)
            }
        }
        .opacity(decayOpacity)
        .contentShape(Rectangle())
        .onTapGesture { onReadMoreTap?() }
        .contextMenu {
            if article.clusterSize > 1, let onSplitCluster {
                Button {
                    onSplitCluster()
                } label: {
                    Label("Show as separate stories", systemImage: "arrow.triangle.branch")
                }
            }

            if let onBookmarkTap {
                Button {
                    onBookmarkTap()
                } label: {
                    Label(
                        article.isBookmarked ? "Remove Bookmark" : "Bookmark",
                        systemImage: article.isBookmarked ? "bookmark.slash" : "bookmark"
                    )
                }
            }
        }
        .task(id: article.id) {
            guard article.imageURL == nil else { return }
            if let cached = await OGImageService.shared.cachedImageURL(for: article.articleURL) {
                ogImageURL = cached
                return
            }
            await OGImageService.shared.prefetch(articleURL: article.articleURL)
            ogImageURL = await OGImageService.shared.cachedImageURL(for: article.articleURL)
        }
    }

    // MARK: - Decay Opacity

    private var decayOpacity: Double {
        let minOpacity = 0.5
        let normalizedScore = (decayScore - 0.2) / 0.8
        return minOpacity + normalizedScore * (1.0 - minOpacity)
    }

    // MARK: - Subviews

    private var heroImage: some View {
        Color.clear
            .frame(maxWidth: .infinity)
            .frame(height: 180)
            .overlay {
                ZStack {
                    if !heroImageLoaded {
                        placeholderHero
                    }

                    let displayURL = article.imageURL ?? ogImageURL
                    if let urlString = displayURL, let url = URL(string: urlString) {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .success(let image):
                                image
                                    .resizable()
                                    .scaledToFill()
                                    .onAppear { heroImageLoaded = true }
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
            }
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

            Text("\(source?.name ?? "Unknown") • \(article.relativeTimeString)")
                .font(Design.Typography.caption)
                .foregroundStyle(Design.Colors.secondaryText)
                .textCase(.uppercase)
                .tracking(0.5)
        }
    }

    // MARK: - Cluster Badge

    @ViewBuilder
    private func clusterBadgeChip(_ badge: ClusterBadge) -> some View {
        let isExpandable = !badge.siblings.isEmpty && badge.onSiblingTap != nil

        if isExpandable {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isClusterExpanded.toggle()
                }
            } label: {
                clusterBadgeChipContent(badge, isExpandable: true)
            }
            .buttonStyle(.plain)
        } else {
            clusterBadgeChipContent(badge, isExpandable: false)
        }
    }

    private func clusterBadgeChipContent(_ badge: ClusterBadge, isExpandable: Bool) -> some View {
        let symbol: String = {
            switch badge.style {
            case .sources, .updates: return "newspaper.fill"
            case .clustered:         return "link"
            }
        }()
        let isMuted = badge.style == .clustered
        let fg: Color = isMuted ? Design.Colors.secondaryText : Design.Colors.primary
        let bg: Color = isMuted
            ? Design.Colors.secondaryText.opacity(0.12)
            : Design.Colors.primary.opacity(0.15)

        return HStack(spacing: 4) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .semibold))
            Text(badge.label)
                .font(Design.Typography.caption)
                .italic(isMuted)
            if isExpandable {
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .rotationEffect(.degrees(isClusterExpanded ? 180 : 0))
            }
        }
        .foregroundStyle(fg)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: Design.Radius.small)
                .fill(bg)
        )
    }

    /// Inline picker list shown when the cluster chip is expanded.
    private func clusterSiblingList(_ badge: ClusterBadge) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(badge.siblings) { sibling in
                Button {
                    badge.onSiblingTap?(sibling.article)
                } label: {
                    HStack(alignment: .top, spacing: 8) {
                        Circle()
                            .fill(Design.Colors.primary.opacity(0.6))
                            .frame(width: 4, height: 4)
                            .padding(.top, 7)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(sibling.article.title)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(Design.Colors.primaryText(for: colorScheme))
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                            Text("\(sibling.sourceName) · \(sibling.article.relativeTimeString)")
                                .font(.system(size: 11))
                                .foregroundStyle(Design.Colors.secondaryText)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Design.Colors.secondaryText.opacity(0.6))
                            .padding(.top, 3)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, 4)
        .padding(.leading, 2)
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    private var titleText: some View {
        Text(article.title)
            .font(Design.Typography.cardTitle)
            .foregroundStyle(Design.Colors.primaryText(for: colorScheme))
            .lineLimit(appState.showImages ? 2 : 3)
            .tracking(-0.3)
    }

    private var excerptText: some View {
        Text(article.excerpt)
            .font(Design.Typography.body)
            .foregroundStyle(Design.Colors.secondaryText)
            .lineLimit(2)
            .lineSpacing(2)
    }

    // MARK: - Paywall Detection

    private var isPaywalled: Bool {
        article.isPaywalled || source?.isPaywalled == true
    }

    private var paywallBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: "lock.fill")
                .font(.system(size: 10))
            Text("Subscription may be required")
                .font(Design.Typography.caption)
        }
        .foregroundStyle(Design.Colors.secondaryText)
    }

    private var footerRow: some View {
        HStack(spacing: 16) {
            Button {
                onBookmarkTap?()
            } label: {
                Image(systemName: article.isBookmarked ? Design.Icons.bookmarkFilled : Design.Icons.bookmark)
                    .font(.system(size: 18))
                    .foregroundStyle(article.isBookmarked ? Color.orange : Design.Colors.secondaryText)
                    .scaleEffect(article.isBookmarked ? 1.15 : 1.0)
                    .animation(.spring(response: 0.3, dampingFraction: 0.5), value: article.isBookmarked)
            }
            .buttonStyle(.plain)

            if let url = URL(string: article.articleURL) {
                ShareLink(
                    item: url,
                    subject: Text(article.title),
                    message: Text(article.title)
                ) {
                    Image(systemName: Design.Icons.share)
                        .font(.system(size: 18))
                        .foregroundStyle(Design.Colors.secondaryText)
                }
                .buttonStyle(.plain)
            }

            Spacer()
        }
        .padding(.top, Design.Spacing.small)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Design.Colors.subtleBorder)
                .frame(height: 1)
        }
    }
}

// MARK: - Preview

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()

        ScrollView {
            VStack(spacing: Design.Spacing.cardGap) {
                ArticleCardView(
                    article: Article(
                        title: "Compact Row — No Images",
                        excerpt: "This preview tests the compact list format.",
                        sourceID: UUID(), categoryID: UUID(),
                        publishedAt: Date(), isRead: false, isBookmarked: false, readTimeMinutes: 3
                    ),
                    source: Source(
                        name: "Wired", feedURL: "https://wired.com/feed/",
                        icon: "wifi", iconColor: .purple, categoryID: UUID()
                    )
                )
                .environment(AppState())

                ArticleCardView(
                    article: Article(
                        title: "The Future of AI is Local",
                        excerpt: "Privacy-focused on-device processing is becoming the new standard for modern mobile applications.",
                        sourceID: UUID(),
                        categoryID: UUID(),
                        publishedAt: Date().addingTimeInterval(-2 * 3600),
                        isRead: false,
                        isBookmarked: false,
                        readTimeMinutes: 6
                    ),
                    source: Source(
                        name: "TechCrunch",
                        feedURL: "https://techcrunch.com/feed/",
                        icon: "bolt.fill",
                        iconColor: .blue,
                        categoryID: UUID()
                    )
                )
                .environment(AppState())

                ArticleCardView(
                    article: Article(
                        title: "Mastering Liquid Glass Effects",
                        excerpt: "How to achieve perfect translucency and background blurs in your next mobile project.",
                        sourceID: UUID(),
                        categoryID: UUID(),
                        publishedAt: Date().addingTimeInterval(-5 * 3600),
                        isRead: true,
                        isBookmarked: true,
                        readTimeMinutes: 8
                    ),
                    source: Source(
                        name: "Smashing Magazine",
                        feedURL: "https://smashingmagazine.com/feed/",
                        icon: "paintbrush.fill",
                        iconColor: .orange,
                        categoryID: UUID()
                    )
                )
                .environment(AppState())
            }
            .padding(Design.Spacing.edge)
        }
    }
}
