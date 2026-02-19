//
//  ArticleReaderHostView.swift
//  OpenRSS
//
//  Intermediate view that runs the article pipeline for a given Article
//  and presents ArticleReaderView when processing is complete.
//
//  States:
//    .loading  — spinner while pipeline fetches + extracts + normalises
//    .loaded   — ArticleReaderView with the ExtractedArticle
//    .failed   — error message + "Open in Safari" fallback button
//

import SwiftUI
import SwiftData

struct ArticleReaderHostView: View {

    // MARK: - Input

    /// The existing app Article (from the RSS feed card list).
    let article: Article
    /// Human-readable feed name shown in the reader header.
    let feedName: String

    // MARK: - State

    private enum LoadState {
        case loading
        case loaded(ExtractedArticle)
        case failed(String)
    }

    @State private var loadState: LoadState = .loading

    // MARK: - Environment

    @Environment(\.modelContext) private var modelContext
    @Environment(AppState.self)  private var appState

    // MARK: - Body

    var body: some View {
        Group {
            switch loadState {
            case .loading:
                loadingView

            case .loaded(let extracted):
                ArticleReaderView(extracted: extracted)

            case .failed(let message):
                errorView(message: message)
            }
        }
        .task { await runPipeline() }
        .onAppear  { appState.isReadingArticle = true  }
        .onDisappear { appState.isReadingArticle = false }
    }

    // MARK: - Loading View

    private var loadingView: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.4)

            Text("Loading article…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
    }

    // MARK: - Error View

    private func errorView(message: String) -> some View {
        VStack(spacing: 24) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48, weight: .ultraLight))
                .foregroundStyle(.secondary)

            VStack(spacing: 8) {
                Text("Couldn't load article")
                    .font(.headline)

                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            if let url = URL(string: article.articleURL) {
                Link(destination: url) {
                    Label("Open in Safari", systemImage: "safari")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(Color.accentColor, in: Capsule())
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
    }

    // MARK: - Pipeline

    @MainActor
    private func runPipeline() async {
        guard let url = URL(string: article.articleURL) else {
            loadState = .failed("The article link is invalid.")
            return
        }

        // Wrap the app's Article into the pipeline's RSSItem
        let item = RSSItem(
            id:          article.id,
            title:       article.title,
            author:      nil,
            publishDate: article.publishedAt,
            summary:     article.excerpt,
            sourceURL:   url,
            feedName:    feedName
        )

        let pipeline = ArticlePipelineService(context: modelContext)

        do {
            let extracted = try await pipeline.process(item: item)
            loadState = .loaded(extracted)
        } catch {
            loadState = .failed(error.localizedDescription)
        }
    }
}
