//
//  SourceFeedView.swift
//  OpenRSS
//
//  Full chronological, unfiltered view of all articles from a single source.
//

import SwiftUI

struct SourceFeedView: View {

    // MARK: - ViewModel

    @State private var viewModel: SourceFeedViewModel
    @State private var selectedArticle: Article? = nil

    // MARK: - Environment

    @Environment(\.colorScheme) private var colorScheme

    // MARK: - Initialization

    init(sourceID: UUID) {
        _viewModel = State(initialValue: SourceFeedViewModel(sourceID: sourceID))
    }

    // MARK: - Body

    var body: some View {
        ZStack(alignment: .top) {
            Design.Colors.background(for: colorScheme).ignoresSafeArea()

            ScrollView {
                LazyVStack(spacing: Design.Spacing.cardGap) {
                    // Source header
                    if let source = viewModel.source {
                        sourceHeader(source)
                    }

                    // Articles
                    if viewModel.articles.isEmpty {
                        emptyState
                    } else {
                        ForEach(viewModel.articles) { article in
                            ArticleCardView(
                                article: article,
                                source: viewModel.source,
                                decayScore: 1.0,
                                clusterBadge: article.isCanonical
                                    ? nil
                                    : ClusterBadge(label: "Clustered", style: .clustered),
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
        .navigationTitle(viewModel.source?.name ?? "Source")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $selectedArticle) { article in
            ArticleReaderHostView(
                article: article,
                feedName: viewModel.source?.name ?? "Article"
            )
        }
    }

    // MARK: - Source Header

    private func sourceHeader(_ source: Source) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(source.iconColor.opacity(0.15))
                        .frame(width: 52, height: 52)
                    Image(systemName: source.icon)
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(source.iconColor)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(source.name)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(Design.Colors.primaryText(for: colorScheme))

                    Text("\(source.effectiveVelocityTier.displayName) · \(source.effectiveVelocityTier.shortDescription) half-life · \(viewModel.articleCount) article\(viewModel.articleCount == 1 ? "" : "s")")
                        .font(.system(size: 13))
                        .foregroundStyle(Design.Colors.secondaryText(for: colorScheme))
                }
            }

            Text("Subscribed \(source.addedAt.formatted(.dateTime.month(.abbreviated).day().year()))")
                .font(.system(size: 12))
                .foregroundStyle(Design.Colors.secondaryText(for: colorScheme).opacity(0.7))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Design.Spacing.edge)
        .padding(.bottom, 8)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: Design.Spacing.small) {
            Image(systemName: "doc.text")
                .font(.system(size: 36, weight: .ultraLight))
                .foregroundStyle(Design.Colors.secondaryText(for: colorScheme).opacity(0.6))

            Text("No Articles")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Design.Colors.primaryText(for: colorScheme))

            Text("No cached articles from this source.")
                .font(.system(size: 14))
                .foregroundStyle(Design.Colors.secondaryText(for: colorScheme))
        }
        .padding(.top, 60)
        .frame(maxWidth: .infinity)
    }
}

#Preview {
    NavigationStack {
        SourceFeedView(sourceID: UUID())
    }
}
