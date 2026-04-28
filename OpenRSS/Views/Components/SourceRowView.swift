//
//  SourceRowView.swift
//  OpenRSS
//
//  Created by Darius Ehsani on 2/3/26.
//

import SwiftUI

/// Individual source row for the Sources tab
struct SourceRowView: View {

    // MARK: - Properties

    let source: Source
    let unreadCount: Int
    /// Called when the user taps the row (used for sourceBrowse affinity tracking).
    var onTap: (() -> Void)?

    // MARK: - Body

    var body: some View {
        HStack(spacing: 12) {
            // Source icon
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(source.iconColor.opacity(0.15))
                    .frame(width: 40, height: 40)

                Image(systemName: source.icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(source.iconColor)
            }

            // Source info
            VStack(alignment: .leading, spacing: 2) {
                Text(source.name)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.white)

                Text(source.websiteURL)
                    .font(.system(size: 12))
                    .foregroundStyle(Design.Colors.secondaryText)
                    .lineLimit(1)
            }

            Spacer()

            // Unread count badge
            if unreadCount > 0 {
                Text("\(unreadCount)")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Design.Colors.primary)
                    .clipShape(Capsule())
            }

            // Chevron
            Image(systemName: Design.Icons.chevronRight)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Design.Colors.secondaryText.opacity(0.5))
        }
        .padding(.vertical, 8)
        .padding(.horizontal, Design.Spacing.edge)
        .contentShape(Rectangle())
        .onTapGesture { onTap?() }
    }
}

// MARK: - Category Section Header

/// Expandable category header for the Sources tab
struct CategorySectionHeader: View {

    // MARK: - Properties

    let category: Category
    let sourceCount: Int
    let unreadCount: Int
    let isExpanded: Bool
    var onTap: (() -> Void)?
    var onBrowse: (() -> Void)?

    // MARK: - Body

    var body: some View {
        Button {
            onTap?()
        } label: {
            HStack(spacing: 12) {
                // Category icon
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(category.color.opacity(0.15))
                        .frame(width: 44, height: 44)

                    Image(systemName: category.icon)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(category.color)
                }

                // Category info
                VStack(alignment: .leading, spacing: 2) {
                    Text(category.name)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)

                    Text("\(sourceCount) sources")
                        .font(.system(size: 13))
                        .foregroundStyle(Design.Colors.secondaryText)
                }

                Spacer()

                // Unread count badge
                if unreadCount > 0 {
                    Text("\(unreadCount)")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(Design.Colors.primary)
                        .clipShape(Capsule())
                }

                // Browse folder
                if let onBrowse {
                    Button {
                        onBrowse()
                    } label: {
                        Image(systemName: "rectangle.grid.1x2")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Design.Colors.primary.opacity(0.8))
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.plain)
                }

                // Expand/collapse chevron
                Image(systemName: isExpanded ? Design.Icons.chevronDown : Design.Icons.chevronRight)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Design.Colors.secondaryText)
                    .rotationEffect(.degrees(isExpanded ? 0 : 0))
            }
            .padding(.vertical, 12)
            .padding(.horizontal, Design.Spacing.edge)
            .background(Design.Colors.cardBackground.opacity(0.5))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Preview

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()

        VStack(spacing: 0) {
            CategorySectionHeader(
                category: Category(name: "Tech News", icon: "cpu.fill", color: .blue),
                sourceCount: 4,
                unreadCount: 12,
                isExpanded: true
            )

            SourceRowView(
                source: Source(
                    name: "TechCrunch",
                    feedURL: "https://techcrunch.com/feed/",
                    websiteURL: "https://techcrunch.com",
                    icon: "bolt.fill",
                    iconColor: .blue,
                    categoryID: UUID()
                ),
                unreadCount: 5
            )

            SourceRowView(
                source: Source(
                    name: "The Verge",
                    feedURL: "https://theverge.com/rss/index.xml",
                    websiteURL: "https://theverge.com",
                    icon: "v.circle.fill",
                    iconColor: .purple,
                    categoryID: UUID()
                ),
                unreadCount: 0
            )

            Divider().background(Design.Colors.subtleBorder)

            CategorySectionHeader(
                category: Category(name: "Design", icon: "paintbrush.fill", color: .orange),
                sourceCount: 3,
                unreadCount: 8,
                isExpanded: false
            )
        }
    }
}
