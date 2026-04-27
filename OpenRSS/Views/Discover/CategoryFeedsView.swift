//
//  CategoryFeedsView.swift
//  OpenRSS
//
//  Sheet displayed when the user taps a category card in the Discover tab.
//  Lists all feeds in that category; each row has an Add (+) or Already Added (✓)
//  indicator. Tapping (+) presents QuickAddFeedSheet.
//

import SwiftUI

struct CategoryFeedsView: View {

    // MARK: - Properties

    let category: CatalogCategory

    // MARK: - State

    @State private var feedToAdd: CatalogFeed? = nil
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    // MARK: - Derived

    /// Lowercased set of feed URLs the user is already subscribed to.
    private var subscribedURLs: Set<String> {
        Set(SwiftDataService.shared.sources.map { $0.feedURL.lowercased() })
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ZStack {
                Design.Colors.background(for: colorScheme).ignoresSafeArea()

                VStack(spacing: 0) {
                    categoryHeader
                        .frame(maxWidth: .infinity, alignment: .leading)

                    List {
                        ForEach(category.feeds) { feed in
                            feedRow(feed)
                                .listRowBackground(Design.Colors.cardBackground(for: colorScheme))
                        }
                    }
                    .listStyle(.insetGrouped)
                    .scrollContentBackground(.hidden)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                        .foregroundStyle(Design.Colors.primary)
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationBackground(colorScheme == .dark ? .ultraThinMaterial : .regularMaterial)
        .presentationCornerRadius(Design.Radius.glass)
        .sheet(item: $feedToAdd) { feed in
            QuickAddFeedSheet(feed: feed)
        }
    }

    // MARK: - Category Header

    private var categoryHeader: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(category.color.opacity(0.15))
                    .frame(width: 48, height: 48)
                Image(systemName: category.icon)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(category.color)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(category.name)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(Design.Colors.primaryText(for: colorScheme))
                Text("\(category.feeds.count) sources")
                    .font(.system(size: 13))
                    .foregroundStyle(Design.Colors.secondaryText(for: colorScheme))
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 16)
    }

    // MARK: - Feed Row

    private func feedRow(_ feed: CatalogFeed) -> some View {
        let isSubscribed = subscribedURLs.contains(feed.feedURL.lowercased())

        return HStack(spacing: 12) {
            // Feed info
            VStack(alignment: .leading, spacing: 3) {
                Text(feed.name)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Design.Colors.primaryText(for: colorScheme))

                Text(feed.description)
                    .font(.system(size: 13))
                    .foregroundStyle(Design.Colors.secondaryText(for: colorScheme))
                    .lineLimit(2)
            }

            Spacer()

            // Add / Added indicator
            if isSubscribed {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(.green)
            } else {
                Button {
                    feedToAdd = feed
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Design.Colors.primary)
                        .frame(width: 32, height: 32)
                        .background(Design.Colors.primary.opacity(0.12))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 6)
    }
}

// MARK: - Preview

#Preview {
    Color.clear
        .sheet(isPresented: .constant(true)) {
            CategoryFeedsView(category: RSSCatalog.techCategory)
        }
}
