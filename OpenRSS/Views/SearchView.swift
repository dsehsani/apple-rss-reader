//
//  SearchView.swift
//  OpenRSS
//
//  Native search tab content — shows category grid when idle,
//  filtered article results when the user types a query.
//  Tapping a folder drills into that folder's articles (scoped search).
//

import SwiftUI

struct SearchView: View {

    @Binding var searchText: String

    @Environment(\.colorScheme) private var colorScheme
    @Environment(AppState.self)  private var appState

    // MARK: - Data

    @State private var viewModel = RiverViewModel()

    /// When set, the view is in "folder mode" — search is scoped to this category.
    @State private var selectedCategory: Category? = nil

    /// The article to navigate to in the reader.
    @State private var selectedArticle: Article? = nil

    private var isActive: Bool {
        !searchText.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// Articles filtered by the active folder scope and/or search text.
    private var matchingArticles: [Article] {
        var articles = viewModel.allArticles

        // Scope to the drilled-in folder if one is selected
        if let category = selectedCategory {
            articles = articles.filter { $0.categoryID == category.id }
        }

        // Further filter by search text when the user is typing
        if isActive {
            let query = searchText.lowercased()
            articles = articles.filter {
                $0.title.lowercased().contains(query) ||
                $0.excerpt.lowercased().contains(query)
            }
        }

        return articles
    }

    // MARK: - Body

    var body: some View {
        ScrollView(showsIndicators: false) {
            if let category = selectedCategory {
                folderSearchView(category)
            } else if isActive {
                searchResultsView
            } else {
                browseTopicsView
            }
        }
        .background(Design.Colors.background(for: colorScheme))
        .navigationDestination(item: $selectedArticle) { article in
            ArticleReaderHostView(
                article: article,
                feedName: viewModel.source(for: article)?.name ?? "Article"
            )
        }
        .onAppear {
            // When the user switches to the Search tab while a specific folder
            // is selected in TodayView, auto-scope the search to that folder.
            if let categoryID = appState.activeFolderCategoryID {
                let category = viewModel.allCategories.first { $0.id == categoryID }
                if let category {
                    selectedCategory = category
                }
            }
        }
    }

    // MARK: - Browse Topics (idle state)

    private var browseTopicsView: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Browse by Folder")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(Design.Colors.primaryText(for: colorScheme))
                .padding(.horizontal, 4)

            ForEach(viewModel.allCategories.filter { $0.id != Category.allUpdates.id }) { category in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedCategory = category
                    }
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: category.icon)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 40, height: 40)
                            .background(category.color.gradient)
                            .clipShape(RoundedRectangle(cornerRadius: 10))

                        Text(category.name)
                            .font(.system(size: 17, weight: .medium))
                            .foregroundStyle(Design.Colors.primaryText(for: colorScheme))

                        Spacer()

                        let count = viewModel.unreadCount(for: category)
                        if count > 0 {
                            Text("\(count)")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Design.Colors.secondaryText(for: colorScheme))
                        }

                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Design.Colors.secondaryText(for: colorScheme).opacity(0.5))
                    }
                    .padding(.horizontal, Design.Spacing.edge)
                    .padding(.vertical, 12)
                    .background(Design.Colors.cardBackground(for: colorScheme))
                    .clipShape(RoundedRectangle(cornerRadius: Design.Radius.standard))
                    .overlay(
                        RoundedRectangle(cornerRadius: Design.Radius.standard)
                            .stroke(Design.Colors.glassBorder(for: colorScheme), lineWidth: 0.5)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, Design.Spacing.edge)
        .padding(.top, 8)
        .padding(.bottom, 100)
    }

    // MARK: - Folder Search Mode

    private func folderSearchView(_ category: Category) -> some View {
        VStack(spacing: 0) {
            // Folder header with back button
            HStack(spacing: 12) {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedCategory = nil
                        searchText = ""
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 14, weight: .semibold))
                        Text("All Folders")
                            .font(.system(size: 15))
                    }
                    .foregroundStyle(Design.Colors.primary)
                }
                .buttonStyle(.plain)

                Spacer()
            }
            .padding(.horizontal, Design.Spacing.edge)
            .padding(.top, 8)
            .padding(.bottom, 12)

            // Folder identity row
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
                    Text(isActive
                         ? "\(matchingArticles.count) result\(matchingArticles.count == 1 ? "" : "s")"
                         : "\(matchingArticles.count) article\(matchingArticles.count == 1 ? "" : "s")")
                        .font(.system(size: 13))
                        .foregroundStyle(Design.Colors.secondaryText(for: colorScheme))
                }

                Spacer()
            }
            .padding(.horizontal, Design.Spacing.edge)
            .padding(.bottom, 16)

            articleList(articles: matchingArticles,
                        emptyMessage: isActive
                            ? "No articles found for \"\(searchText)\" in \(category.name)"
                            : "No articles in \(category.name)")
        }
    }

    // MARK: - Global Search Results

    private var searchResultsView: some View {
        VStack(spacing: 0) {
            if matchingArticles.isEmpty {
                VStack(spacing: 16) {
                    Spacer().frame(height: 60)
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 40, weight: .ultraLight))
                        .foregroundStyle(Design.Colors.secondaryText(for: colorScheme).opacity(0.6))
                    Text("No articles found for \"\(searchText)\"")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(Design.Colors.secondaryText(for: colorScheme))
                        .multilineTextAlignment(.center)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, Design.Spacing.edge)
            } else {
                HStack {
                    Text("\(matchingArticles.count) result\(matchingArticles.count == 1 ? "" : "s")")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Design.Colors.secondaryText(for: colorScheme))
                    Spacer()
                }
                .padding(.horizontal, Design.Spacing.edge)
                .padding(.top, 8)
                .padding(.bottom, 12)

                articleList(articles: matchingArticles, emptyMessage: nil)
            }
        }
    }

    // MARK: - Shared Article List

    @ViewBuilder
    private func articleList(articles: [Article], emptyMessage: String?) -> some View {
        if articles.isEmpty, let message = emptyMessage {
            VStack(spacing: 16) {
                Spacer().frame(height: 40)
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 40, weight: .ultraLight))
                    .foregroundStyle(Design.Colors.secondaryText(for: colorScheme).opacity(0.6))
                Text(message)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Design.Colors.secondaryText(for: colorScheme))
                    .multilineTextAlignment(.center)
                Spacer()
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, Design.Spacing.edge)
        } else {
            LazyVStack(spacing: Design.Spacing.cardGap) {
                ForEach(articles) { article in
                    if let source = viewModel.source(for: article) {
                        ArticleCardView(
                            article: article,
                            source: source,
                            onBookmarkTap: { viewModel.toggleBookmark(for: article) },
                            onReadMoreTap: {
                                viewModel.markAsRead(article)
                                selectedArticle = article
                            }
                        )
                        .padding(.horizontal, Design.Spacing.edge)
                    }
                }
            }
            .padding(.bottom, 100)
        }
    }
}
