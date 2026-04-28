//
//  FolderDetailView.swift
//  OpenRSS
//
//  Clean list of feeds inside a folder.
//  Swipe left on any feed row to remove it from the folder.
//

import SwiftUI

struct FolderDetailView: View {

    // MARK: - Properties

    let folder: Category

    // MARK: - State

    @State private var viewModel = MyFeedsViewModel()

    // MARK: - Environment

    @Environment(\.colorScheme) private var colorScheme

    // MARK: - Body

    var body: some View {
        let feeds: [Source] = {
            if folder.id == SwiftDataService.unfiledFolderID {
                return viewModel.unfiledFeeds
            }
            return viewModel.feeds(in: folder)
        }()

        ZStack {
            Design.Colors.background(for: colorScheme).ignoresSafeArea()

            if feeds.isEmpty {
                VStack(spacing: 14) {
                    Image(systemName: "tray")
                        .font(.system(size: 36, weight: .ultraLight))
                        .foregroundStyle(Design.Colors.secondaryText(for: colorScheme).opacity(0.4))

                    Text("No feeds in this folder")
                        .font(.system(size: 15))
                        .foregroundStyle(Design.Colors.secondaryText(for: colorScheme))
                }
            } else {
                List {
                    ForEach(feeds) { feed in
                        feedRow(feed)
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    withAnimation {
                                        viewModel.deleteFeed(feed)
                                    }
                                } label: {
                                    Image(systemName: "trash")
                                }
                            }
                            .listRowBackground(
                                Design.Colors.cardBackground(for: colorScheme)
                            )
                            .listRowSeparatorTint(
                                Design.Colors.glassBorder(for: colorScheme)
                            )
                    }
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
            }
        }
        .navigationTitle(folder.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Feed Row

    private func feedRow(_ feed: Source) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(feed.iconColor.opacity(0.15))
                    .frame(width: 38, height: 38)
                Image(systemName: feed.icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(feed.iconColor)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(feed.name)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Design.Colors.primaryText(for: colorScheme))
                    .lineLimit(1)

                Text(feed.websiteURL)
                    .font(.system(size: 12))
                    .foregroundStyle(Design.Colors.secondaryText(for: colorScheme))
                    .lineLimit(1)
            }

            Spacer()

            if feed.isPaywalled {
                Image(systemName: "lock.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(Design.Colors.secondaryText(for: colorScheme).opacity(0.6))
            }

            if !feed.isEnabled {
                Image(systemName: "pause.circle")
                    .font(.system(size: 14))
                    .foregroundStyle(Design.Colors.secondaryText(for: colorScheme).opacity(0.6))
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    NavigationStack {
        FolderDetailView(
            folder: Category(name: "Tech", icon: "laptopcomputer", color: .blue)
        )
    }
}
