//
//  FolderRowView.swift
//  OpenRSS
//
//  FeedItemRowView — individual feed row used inside an expanded folder card
//  and in the search results list.
//
//  Note: FolderRowView was replaced by the inline folderCard(_:) function
//  in MyFeedsView, which gives tighter control over the glass card state.
//

import SwiftUI

// MARK: - FeedItemRowView

/// A single feed row displayed inside an expanded folder card.
/// Background is transparent so the parent glass card shows through.
struct FeedItemRowView: View {

    let feed:      Source
    let viewModel: MyFeedsViewModel

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 10) {

            // Feed icon chip
            ZStack {
                RoundedRectangle(cornerRadius: 7)
                    .fill(feed.iconColor.opacity(0.15))
                    .frame(width: 30, height: 30)
                Image(systemName: feed.icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(feed.iconColor)
            }

            // Feed name + URL
            VStack(alignment: .leading, spacing: 1) {
                Text(feed.name)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Design.Colors.primaryText(for: colorScheme))
                    .lineLimit(1)
                Text(feed.websiteURL)
                    .font(.system(size: 11))
                    .foregroundStyle(Design.Colors.secondaryText(for: colorScheme))
                    .lineLimit(1)
            }

            Spacer()

            // Paused indicator
            if !feed.isEnabled {
                Image(systemName: "pause.circle")
                    .font(.system(size: 14))
                    .foregroundStyle(Design.Colors.secondaryText(for: colorScheme).opacity(0.6))
            }
        }
        .padding(.vertical, 9)
        .padding(.horizontal, Design.Spacing.edge)
        // Transparent — parent glass card provides the background
        .background(Color.clear)
        .contentShape(Rectangle())
    }
}

// MARK: - Preview

#Preview {
    let source = Source(
        id: UUID(),
        name: "The Verge",
        feedURL: "https://www.theverge.com/rss/index.xml",
        websiteURL: "https://www.theverge.com",
        icon: "dot.radiowaves.left.and.right",
        iconColor: .blue,
        categoryID: UUID(),
        isEnabled: true,
        addedAt: Date()
    )
    return ZStack {
        Color(hex: "0a0e14").ignoresSafeArea()
        RoundedRectangle(cornerRadius: 16)
            .fill(.ultraThinMaterial)
            .frame(height: 64)
            .padding()
            .overlay {
                FeedItemRowView(feed: source, viewModel: MyFeedsViewModel())
                    .padding()
            }
    }
}
