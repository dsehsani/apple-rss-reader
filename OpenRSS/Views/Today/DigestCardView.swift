//
//  DigestCardView.swift
//  OpenRSS
//
//  Phase 2c — Condensed card for overflow articles from a single source.
//  Shows source name, overflow count, tappable article links, and a
//  "Go to [source]" button to explore the full feed.
//

import SwiftUI

// MARK: - DigestCardView

struct DigestCardView: View {

    // MARK: - Properties

    let digest: DigestCard
    let source: Source?
    var onArticleTap: ((FeedItem) -> Void)?
    var onGoToSource: (() -> Void)?

    // MARK: - Environment

    @Environment(\.colorScheme) private var colorScheme

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                sourceInfoRow
                overflowLabel
                articleLinks
                goToSourceButton
            }
            .padding(Design.Spacing.cardPadding)
        }
        .cardStyle(for: colorScheme)
        .overlay(
            // Accent stripe on left edge
            RoundedRectangle(cornerRadius: Design.Radius.standard)
                .fill(Color.clear)
                .overlay(alignment: .leading) {
                    UnevenRoundedRectangle(
                        topLeadingRadius: Design.Radius.standard,
                        bottomLeadingRadius: Design.Radius.standard,
                        bottomTrailingRadius: 0,
                        topTrailingRadius: 0
                    )
                    .fill((source?.iconColor ?? Design.Colors.primary).opacity(0.6))
                    .frame(width: 4)
                }
                .clipShape(RoundedRectangle(cornerRadius: Design.Radius.standard))
        )
    }

    // MARK: - Subviews

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

            Text(source?.name ?? digest.sourceName)
                .font(Design.Typography.caption)
                .foregroundStyle(Design.Colors.secondaryText(for: colorScheme))
                .textCase(.uppercase)
                .tracking(0.5)
        }
    }

    private var overflowLabel: some View {
        HStack(spacing: 6) {
            Image(systemName: "tray.full.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(source?.iconColor ?? Design.Colors.primary)

            Text("\(digest.itemCount) more article\(digest.itemCount == 1 ? "" : "s")")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Design.Colors.primaryText(for: colorScheme))
        }
    }

    private var articleLinks: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Array(digest.overflowItems.prefix(4)), id: \.id) { item in
                Button {
                    onArticleTap?(item)
                } label: {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(source?.iconColor ?? Design.Colors.primary)
                            .padding(.top, 5)

                        Text(item.title)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Design.Colors.primaryText(for: colorScheme))
                            .lineLimit(1)
                            .multilineTextAlignment(.leading)

                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var goToSourceButton: some View {
        Button {
            onGoToSource?()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "arrow.right.circle.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(source?.iconColor ?? Design.Colors.primary)

                Text("Go to \(source?.name ?? digest.sourceName)")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(source?.iconColor ?? Design.Colors.primary)

                Spacer()

                Image(systemName: Design.Icons.chevronRight)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Design.Colors.secondaryText(for: colorScheme))
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
            .background(
                RoundedRectangle(cornerRadius: Design.Radius.small)
                    .fill((source?.iconColor ?? Design.Colors.primary).opacity(colorScheme == .dark ? 0.1 : 0.08))
            )
        }
        .buttonStyle(.plain)
    }
}
