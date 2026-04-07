//
//  ArchiveView.swift
//  OpenRSS
//
//  Shows articles that have fully decayed and aged out of the Today feed.
//

import SwiftUI

struct ArchiveView: View {

    // MARK: - ViewModel

    @State private var viewModel = ArchiveViewModel()

    // MARK: - State

    @State private var showingSearch = false
    @State private var selectedArticle: Article? = nil

    // MARK: - Environment

    @Environment(\.colorScheme) private var colorScheme

    // MARK: - Body

    var body: some View {
        ZStack(alignment: .top) {
            Design.Colors.background(for: colorScheme).ignoresSafeArea()

            ScrollView {
                LazyVStack(spacing: Design.Spacing.cardGap) {
                    // Description
                    if !viewModel.searchViewModel.hasActiveQuery {
                        Text("Articles that have fully decayed and aged out of the Today feed.")
                            .font(.system(size: 14))
                            .foregroundStyle(Design.Colors.secondaryText(for: colorScheme))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, Design.Spacing.edge)
                    }

                    if viewModel.filteredArticles.isEmpty {
                        emptyState
                    } else {
                        ForEach(viewModel.filteredArticles) { article in
                            ArticleCardView(
                                article: article,
                                source: viewModel.source(for: article),
                                decayScore: 1.0,
                                onBookmarkTap: {
                                    viewModel.toggleBookmark(for: article)
                                },
                                onReadMoreTap: {
                                    viewModel.markAsRead(article)
                                    selectedArticle = article
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
        .navigationTitle("Archive")
        .navigationBarTitleDisplayMode(.large)
        .searchable(
            text: $viewModel.searchViewModel.searchText,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "Search archived articles"
        )
        .navigationDestination(item: $selectedArticle) { article in
            ArticleReaderHostView(
                article: article,
                feedName: viewModel.source(for: article)?.name ?? "Article"
            )
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: Design.Spacing.small) {
            Image(systemName: "archivebox")
                .font(.system(size: 36, weight: .ultraLight))
                .foregroundStyle(Design.Colors.secondaryText(for: colorScheme).opacity(0.6))

            Text("No Archived Articles")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Design.Colors.primaryText(for: colorScheme))

            Text("Articles will appear here after they\nhave fully decayed from the Today feed.")
                .font(.system(size: 14))
                .foregroundStyle(Design.Colors.secondaryText(for: colorScheme))
                .multilineTextAlignment(.center)
        }
        .padding(.top, 60)
        .frame(maxWidth: .infinity)
    }
}

#Preview {
    NavigationStack {
        ArchiveView()
    }
}
