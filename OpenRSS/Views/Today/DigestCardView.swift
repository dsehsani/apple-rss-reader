//
//  DigestCardView.swift
//  OpenRSS
//
//  Phase 2c — Condensed card for overflow articles from a single source.
//  Shows source name, overflow count, 2-3 title highlights, and expands
//  on tap to reveal all overflow article titles.
//

import SwiftUI

// MARK: - DigestCardView

struct DigestCardView: View {

    // MARK: - Properties

    let digest: DigestCard
    let source: Source?

    // MARK: - State

    @State private var isExpanded = false

    // MARK: - Environment

    @Environment(\.colorScheme) private var colorScheme

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Content area
            VStack(alignment: .leading, spacing: Design.Spacing.small) {
                sourceInfoRow
                overflowLabel
                highlightsList
                expandButton
            }
            .padding(Design.Spacing.cardPadding)

            // Expanded list of all overflow titles
            if isExpanded {
                expandedContent
            }
        }
        .cardStyle(for: colorScheme)
        .overlay(
            // Accent stripe on left edge to distinguish digest cards
            RoundedRectangle(cornerRadius: Design.Radius.standard)
                .fill(Color.clear)
                .overlay(alignment: .leading) {
                    UnevenRoundedRectangle(
                        topLeadingRadius: Design.Radius.standard,
                        bottomLeadingRadius: isExpanded ? 0 : Design.Radius.standard,
                        bottomTrailingRadius: 0,
                        topTrailingRadius: 0
                    )
                    .fill(Design.Colors.primary.opacity(0.6))
                    .frame(width: 4)
                }
                .clipShape(RoundedRectangle(cornerRadius: Design.Radius.standard))
        )
    }

    // MARK: - Subviews

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
                .foregroundStyle(Design.Colors.primary)

            Text("\(digest.itemCount) more articles")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Design.Colors.primaryText(for: colorScheme))
        }
    }

    private var highlightsList: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(digest.highlights, id: \.self) { title in
                HStack(alignment: .top, spacing: 8) {
                    Circle()
                        .fill(Design.Colors.secondaryText(for: colorScheme).opacity(0.4))
                        .frame(width: 5, height: 5)
                        .padding(.top, 6)

                    Text(title)
                        .font(Design.Typography.body)
                        .foregroundStyle(Design.Colors.secondaryText(for: colorScheme))
                        .lineLimit(1)
                }
            }
        }
    }

    private var expandButton: some View {
        Button {
            withAnimation(Design.Animation.standard) {
                isExpanded.toggle()
            }
            // Phase 2d — track digest expand
            if isExpanded {
                AffinityTracker.shared.record(
                    .digestExpand,
                    sourceID: digest.sourceID,
                    itemID: UUID() // No single item for digest; use placeholder
                )
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "rectangle.expand.vertical")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Design.Colors.primary)

                Text(isExpanded ? "Show less" : "Show all \(digest.itemCount) articles")
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

    private var expandedContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            Rectangle()
                .fill(colorScheme == .dark ? Design.Colors.subtleBorder : Color.black.opacity(0.06))
                .frame(height: 1)

            VStack(alignment: .leading, spacing: 8) {
                ForEach(digest.highlights, id: \.self) { title in
                    HStack(spacing: 8) {
                        Circle()
                            .fill(Design.Colors.primary.opacity(0.6))
                            .frame(width: 6, height: 6)

                        Text(title)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Design.Colors.primaryText(for: colorScheme))
                            .lineLimit(2)

                        Spacer()
                    }
                }

                if digest.itemCount > digest.highlights.count {
                    Text("+ \(digest.itemCount - digest.highlights.count) more")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Design.Colors.secondaryText(for: colorScheme))
                        .padding(.leading, 14)
                }
            }
            .padding(Design.Spacing.cardPadding)
        }
        .transition(.opacity.combined(with: .move(edge: .top)))
    }
}
