//
//  FolderView.swift
//  OpenRSS
//
//  Browse all articles from feeds in a category/folder with decay sort and filter chips.
//

import SwiftUI

struct FolderView: View {

    // MARK: - ViewModel

    @State private var viewModel: FolderViewModel
    @State private var selectedArticle: Article? = nil

    // MARK: - Environment

    @Environment(\.colorScheme) private var colorScheme

    // MARK: - Initialization

    init(categoryID: UUID) {
        _viewModel = State(initialValue: FolderViewModel(categoryID: categoryID))
    }

    // MARK: - Body

    var body: some View {
        ZStack(alignment: .top) {
            Design.Colors.background(for: colorScheme).ignoresSafeArea()

            ScrollView {
                LazyVStack(spacing: Design.Spacing.cardGap) {
                    // Folder header
                    if let category = viewModel.category {
                        folderHeader(category)
                    }

                    // Filter chips
                    filterChips

                    // Articles
                    if viewModel.filteredArticles.isEmpty {
                        emptyState
                    } else {
                        ForEach(viewModel.filteredArticles) { article in
                            ArticleCardView(
                                article: article,
                                source: viewModel.source(for: article),
                                decayScore: viewModel.decayScore(for: article),
                                clusterBadge: viewModel.clusterBadge(for: article).map { badge in
                                    var b = badge
                                    b.onSiblingTap = { sibling in
                                        viewModel.markAsRead(sibling)
                                        selectedArticle = sibling
                                    }
                                    return b
                                },
                                onBookmarkTap: {
                                    viewModel.toggleBookmark(for: article)
                                },
                                onReadMoreTap: {
                                    viewModel.markAsRead(article)
                                    selectedArticle = article
                                },
                                onSplitCluster: {
                                    viewModel.splitCluster(for: article)
                                }
                            )
                            .padding(.horizontal, Design.Spacing.edge)
                        }
                    }
                }
                .padding(.top, 12)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                Color.clear.frame(height: 20)
            }
        }
        .navigationTitle(viewModel.category?.name ?? "Folder")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $selectedArticle) { article in
            ArticleReaderHostView(
                article: article,
                feedName: viewModel.source(for: article)?.name ?? "Article"
            )
        }
    }

    // MARK: - Folder Header

    private func folderHeader(_ category: Category) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(category.color.opacity(0.15))
                        .frame(width: 52, height: 52)
                    Image(systemName: category.icon)
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(category.color)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(category.name)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(Design.Colors.primaryText(for: colorScheme))

                    Text("\(viewModel.feedCount) feed\(viewModel.feedCount == 1 ? "" : "s") · \(viewModel.totalArticleCount) article\(viewModel.totalArticleCount == 1 ? "" : "s")")
                        .font(.system(size: 13))
                        .foregroundStyle(Design.Colors.secondaryText(for: colorScheme))
                }
            }

            if !viewModel.feedNames.isEmpty {
                Text(viewModel.feedNames)
                    .font(.system(size: 12))
                    .foregroundStyle(Design.Colors.secondaryText(for: colorScheme).opacity(0.7))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Design.Spacing.edge)
        .padding(.bottom, 4)
    }

    // MARK: - Filter Chips

    private var filterChips: some View {
        HStack(spacing: 10) {
            ForEach(FolderViewModel.FolderFilter.allCases, id: \.self) { filter in
                Button {
                    withAnimation(Design.Animation.quick) {
                        viewModel.activeFilter = filter
                    }
                } label: {
                    Text(filter.rawValue)
                        .font(Design.Typography.chip)
                        .foregroundStyle(
                            viewModel.activeFilter == filter
                                ? .white
                                : Design.Colors.secondaryText(for: colorScheme)
                        )
                        .chipStyle(isSelected: viewModel.activeFilter == filter, colorScheme: colorScheme)
                }
                .buttonStyle(.plain)
            }

            Spacer()
        }
        .padding(.horizontal, Design.Spacing.edge)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: Design.Spacing.small) {
            Image(systemName: "folder")
                .font(.system(size: 36, weight: .ultraLight))
                .foregroundStyle(Design.Colors.secondaryText(for: colorScheme).opacity(0.6))

            Text("No Articles")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Design.Colors.primaryText(for: colorScheme))

            Text("No articles match the current filter.")
                .font(.system(size: 14))
                .foregroundStyle(Design.Colors.secondaryText(for: colorScheme))
        }
        .padding(.top, 60)
        .frame(maxWidth: .infinity)
    }
}

#Preview {
    NavigationStack {
        FolderView(categoryID: UUID())
    }
}
