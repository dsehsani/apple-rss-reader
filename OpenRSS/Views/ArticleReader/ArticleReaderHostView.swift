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
        case youtube(URL)
        case playlist(URL)
        case failed(String)
    }

    @State private var loadState: LoadState = .loading
    @State private var isDescriptionExpanded = false

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

            case .youtube(let videoURL):
                youtubeView(videoURL: videoURL)

            case .playlist(let playlistURL):
                playlistView(playlistURL: playlistURL)

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

    // MARK: - YouTube View

    private func youtubeView(videoURL: URL) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {

                // ── Thumbnail ──────────────────────────────────────────
                let videoID = YouTubeService.videoID(from: videoURL.absoluteString)
                let thumbURL = videoID.flatMap { YouTubeService.thumbnailURL(videoID: $0) }

                CachedImageView(
                    url: thumbURL,
                    pointSize: CGSize(width: 400, height: 210),
                    contentMode: .fill
                ) {
                    ZStack {
                        Color(.secondarySystemBackground)
                        Image(systemName: "play.rectangle.fill")
                            .font(.system(size: 48, weight: .ultraLight))
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 210)
                .clipped()

                // ── Title & Channel ────────────────────────────────────
                VStack(alignment: .leading, spacing: 6) {
                    Text(article.title)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 6) {
                        Image(systemName: "play.circle")
                            .font(.system(size: 13))
                            .foregroundStyle(.red)
                        Text(feedName)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(article.relativeTimeString)
                            .font(.system(size: 12))
                            .foregroundStyle(Color(.tertiaryLabel))
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 20)

                Divider().padding(.horizontal, 20)

                // ── Description ────────────────────────────────────────
                if !article.excerpt.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("DESCRIPTION")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color(.tertiaryLabel))
                            .tracking(0.8)

                        Text(article.excerpt)
                            .font(.system(size: 15))
                            .foregroundStyle(.primary)
                            .lineSpacing(5)
                            .lineLimit(isDescriptionExpanded ? nil : 6)
                            .fixedSize(horizontal: false, vertical: true)
                            .animation(.easeInOut(duration: 0.2), value: isDescriptionExpanded)

                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                isDescriptionExpanded.toggle()
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Text(isDescriptionExpanded ? "Show Less" : "Show More")
                                    .font(.system(size: 13, weight: .semibold))
                                Image(systemName: isDescriptionExpanded
                                      ? "chevron.up" : "chevron.down")
                                    .font(.system(size: 11, weight: .semibold))
                            }
                            .foregroundStyle(.red)
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 2)
                    }
                    .padding(16)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(Color(.secondarySystemBackground))
                    )
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                }

                // ── Actions ────────────────────────────────────────────
                VStack(spacing: 12) {
                    Link(destination: videoURL) {
                        HStack(spacing: 8) {
                            Image(systemName: "play.circle.fill")
                                .font(.system(size: 18))
                            Text("Watch on YouTube")
                                .font(.system(size: 16, weight: .semibold))
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.red, in: RoundedRectangle(cornerRadius: 12))
                    }

                    Link(destination: videoURL) {
                        Label("Open in Safari", systemImage: "safari")
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 24)
                .padding(.bottom, 48)
            }
        }
        .background(Color(.systemBackground))
    }

    // MARK: - Playlist View

    private func playlistView(playlistURL: URL) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {

                // ── Playlist Icon ────────────────────────────────────
                ZStack {
                    Color(.secondarySystemBackground)
                    Image(systemName: "list.and.film")
                        .font(.system(size: 48, weight: .ultraLight))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 210)

                // ── Title & Channel ──────────────────────────────────
                VStack(alignment: .leading, spacing: 6) {
                    Text(article.title)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 6) {
                        Image(systemName: "list.bullet.rectangle")
                            .font(.system(size: 13))
                            .foregroundStyle(.red)
                        Text(feedName)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(article.relativeTimeString)
                            .font(.system(size: 12))
                            .foregroundStyle(Color(.tertiaryLabel))
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 20)

                Divider().padding(.horizontal, 20)

                // ── Description ──────────────────────────────────────
                if !article.excerpt.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("DESCRIPTION")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color(.tertiaryLabel))
                            .tracking(0.8)

                        Text(article.excerpt)
                            .font(.system(size: 15))
                            .foregroundStyle(.primary)
                            .lineSpacing(5)
                            .lineLimit(isDescriptionExpanded ? nil : 6)
                            .fixedSize(horizontal: false, vertical: true)
                            .animation(.easeInOut(duration: 0.2), value: isDescriptionExpanded)

                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                isDescriptionExpanded.toggle()
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Text(isDescriptionExpanded ? "Show Less" : "Show More")
                                    .font(.system(size: 13, weight: .semibold))
                                Image(systemName: isDescriptionExpanded
                                      ? "chevron.up" : "chevron.down")
                                    .font(.system(size: 11, weight: .semibold))
                            }
                            .foregroundStyle(.red)
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 2)
                    }
                    .padding(16)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(Color(.secondarySystemBackground))
                    )
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                }

                // ── Actions ──────────────────────────────────────────
                VStack(spacing: 12) {
                    Link(destination: playlistURL) {
                        HStack(spacing: 8) {
                            Image(systemName: "play.circle.fill")
                                .font(.system(size: 18))
                            Text("Open Playlist on YouTube")
                                .font(.system(size: 16, weight: .semibold))
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.red, in: RoundedRectangle(cornerRadius: 12))
                    }

                    Link(destination: playlistURL) {
                        Label("Open in Safari", systemImage: "safari")
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 24)
                .padding(.bottom, 48)
            }
        }
        .background(Color(.systemBackground))
    }

    // MARK: - Pipeline

    @MainActor
    private func runPipeline() async {
        guard let url = URL(string: article.articleURL) else {
            loadState = .failed("The article link is invalid.")
            return
        }

        // YouTube content: skip the pipeline and show the appropriate card.
        switch YouTubeService.route(for: url) {
        case .video, .short:
            loadState = .youtube(url)
            return
        case .playlist:
            loadState = .playlist(url)
            return
        case .unknown:
            break
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

        // Use a fresh context so every CachedArticle the pipeline saves or loads
        // (including its serializedNodes Data blob) is released when the pipeline
        // goes out of scope — rather than staying in the shared main context's
        // row cache for the lifetime of the app.
        let pipeline = ArticlePipelineService(context: ModelContext(modelContext.container))

        do {
            let extracted = try await pipeline.process(item: item)
            loadState = .loaded(extracted)
        } catch {
            // Don't show an error if the user simply navigated away
            guard !Task.isCancelled else { return }
            loadState = .failed(error.localizedDescription)
        }
    }
}
