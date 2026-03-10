//
//  ArticleCardView.swift
//  OpenRSS
//
//  Created by Darius Ehsani on 2/3/26.
//

import SwiftUI

/// Article card component matching the liquid glass design from the schematic
struct ArticleCardView: View {

    // MARK: - Properties

    let article: Article
    let source: Source?
    var onBookmarkTap: (() -> Void)?
    var onReadMoreTap: (() -> Void)?

    // MARK: - Environment (Light/Dark Mode)

    @Environment(\.colorScheme) private var colorScheme

    // MARK: - State

    /// Resolved og:image URL for articles whose RSS feed provided no image.
    /// Set lazily when the card scrolls into view via OGImageService.
    @State private var ogImageURL: String?

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Hero Image
            heroImage

            // Content
            VStack(alignment: .leading, spacing: Design.Spacing.small) {
                sourceInfoRow
                titleText
                excerptText
                if isPaywalled { paywallBadge }
                footerRow
            }
            .padding(Design.Spacing.cardPadding)
        }
        .cardStyle(for: colorScheme)
        .opacity(article.isRead ? 0.7 : 1.0)
        // Whole card is the tap target — child Buttons (bookmark, share) take priority.
        .contentShape(Rectangle())
        .onTapGesture { onReadMoreTap?() }
        // Lazily fetch the og:image when this card scrolls into view.
        // Short-circuits immediately if the RSS feed already provided an image URL.
        // Cancelled automatically if the card scrolls off screen before completing.
        .task(id: article.id) {
            guard article.imageURL == nil else { return }
            // Serve from cache without a network round-trip whenever possible.
            if let cached = await OGImageService.shared.cachedImageURL(for: article.articleURL) {
                ogImageURL = cached
                return
            }
            await OGImageService.shared.prefetch(articleURL: article.articleURL)
            ogImageURL = await OGImageService.shared.cachedImageURL(for: article.articleURL)
        }
    }

    // MARK: - Subviews

    private var heroImage: some View {
        ZStack {
            // Always-visible placeholder so the frame never collapses
            placeholderHero

            // Use the RSS-provided image URL, falling back to the lazily-fetched og:image.
            let displayURL = article.imageURL ?? ogImageURL
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
                        Color.clear   // placeholder already visible underneath
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
            // Source icon
            ZStack {
                RoundedRectangle(cornerRadius: 4)
                    .fill((source?.iconColor ?? .blue).opacity(0.2))
                    .frame(width: 20, height: 20)

                Image(systemName: source?.icon ?? "globe")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(source?.iconColor ?? .blue)
            }

            // Source name and time
            Text("\(source?.name ?? "Unknown") • \(article.relativeTimeString)")
                .font(Design.Typography.caption)
                .foregroundStyle(Design.Colors.secondaryText)
                .textCase(.uppercase)
                .tracking(0.5)
        }
    }

    private var titleText: some View {
        Text(article.title)
            .font(Design.Typography.cardTitle)
            .foregroundStyle(Design.Colors.primaryText(for: colorScheme))
            .lineLimit(2)
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
            // Bookmark button
            Button {
                onBookmarkTap?()
            } label: {
                Image(systemName: article.isBookmarked ? Design.Icons.bookmarkFilled : Design.Icons.bookmark)
                    .font(.system(size: 18))
                    .foregroundStyle(article.isBookmarked ? Design.Colors.primary : Design.Colors.secondaryText)
            }
            .buttonStyle(.plain)

            // Share button — uses native ShareLink so the iOS share sheet
            // appears with the article URL + title pre-filled.
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
            }
            .padding(Design.Spacing.edge)
        }
    }
}
