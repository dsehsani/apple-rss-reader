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
    var onShareTap: (() -> Void)?
    var onReadMoreTap: (() -> Void)?

    // MARK: - State

    @State private var isPressed: Bool = false

    // MARK: - Environment (Light/Dark Mode)

    @Environment(\.colorScheme) private var colorScheme

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Hero Image
            heroImage

            // Content
            VStack(alignment: .leading, spacing: Design.Spacing.small) {
                // Source info row
                sourceInfoRow

                // Title
                titleText

                // Excerpt
                excerptText

                // Footer with actions
                footerRow
            }
            .padding(Design.Spacing.cardPadding)
        }
        .cardStyle(for: colorScheme)
        .opacity(article.isRead ? 0.7 : 1.0)
        .scaleEffect(isPressed ? Design.Animation.pressScale : 1.0)
        .animation(Design.Animation.quick, value: isPressed)
        .onLongPressGesture(minimumDuration: .infinity, pressing: { pressing in
            isPressed = pressing
        }, perform: {})
    }

    // MARK: - Subviews

    private var heroImage: some View {
        ZStack {
            // Always-visible placeholder so the frame never collapses
            placeholderHero

            if let urlString = article.imageURL, let url = URL(string: urlString) {
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

    private var footerRow: some View {
        HStack {
            // Action buttons
            HStack(spacing: 12) {
                // Bookmark button
                Button {
                    onBookmarkTap?()
                } label: {
                    Image(systemName: article.isBookmarked ? Design.Icons.bookmarkFilled : Design.Icons.bookmark)
                        .font(.system(size: 18))
                        .foregroundStyle(article.isBookmarked ? Design.Colors.primary : Design.Colors.secondaryText)
                }
                .buttonStyle(.plain)

                // Share button
                Button {
                    onShareTap?()
                } label: {
                    Image(systemName: Design.Icons.share)
                        .font(.system(size: 18))
                        .foregroundStyle(Design.Colors.secondaryText)
                }
                .buttonStyle(.plain)
            }

            Spacer()

            // Read More button
            Button {
                onReadMoreTap?()
            } label: {
                Text("Read More")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Design.Colors.primary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Design.Colors.primary.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: Design.Radius.small))
            }
            .buttonStyle(.plain)
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
