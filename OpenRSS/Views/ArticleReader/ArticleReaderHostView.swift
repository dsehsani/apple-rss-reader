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
//    .youtube  — YouTube video card
//    .playlist — YouTube playlist card
//    .video    — non-YouTube video card (Vimeo, direct file)
//    .failed   — error message + "Open in Safari" fallback
//

import SwiftUI
import SwiftData
import AVKit

struct ArticleReaderHostView: View {

    // MARK: - Input

    let article: Article
    let feedName: String

    // MARK: - State

    private enum LoadState {
        case loading
        case loaded(ExtractedArticle)
        case youtube(URL)
        case playlist(URL)
        case video(URL, VideoDetector.VideoKind)
        case failed(String)
    }

    @State private var loadState: LoadState = .loading
    @State private var showPaywallSafari = false
    @State private var showChatSheet = false
    @State private var chatViewModel = ChatViewModel()
    @State private var isDescriptionExpanded = false
    @State private var appearedAt: Date?

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
                ArticleReaderView(
                    extracted: extracted,
                    audioURL: article.audioURL.flatMap { URL(string: $0) },
                    videoURL: article.videoURL.flatMap { URL(string: $0) } ?? (article.isVideo ? URL(string: article.articleURL) : nil),
                    onSignIn: { showPaywallSafari = true }
                )

            case .youtube(let videoURL):
                youtubeView(videoURL: videoURL)

            case .playlist(let playlistURL):
                playlistView(playlistURL: playlistURL)

            case .video(let videoURL, let kind):
                videoView(videoURL: videoURL, kind: kind)

            case .failed(let message):
                errorView(message: message)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if case .loaded = loadState {
                chatBubbleButton
                    .padding(.trailing, 20)
                    .padding(.bottom, 30)
            }
        }
        // Chat sheet — anchored on the Group so it presents regardless of LoadState.
        .sheet(isPresented: $showChatSheet, onDismiss: {
            appState.isReadingArticle = true
        }) {
            ChatSheetView(viewModel: chatViewModel)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(20)
        }
        // Paywall sheet — anchored here so it reliably presents regardless of LoadState.
        // onDismiss re-asserts isReadingArticle so presenting the sheet doesn't
        // accidentally trigger a navigation pop in the parent view.
        .sheet(isPresented: $showPaywallSafari, onDismiss: {
            appState.isReadingArticle = true
        }) {
            if let url = URL(string: article.articleURL) {
                SafariView(url: url)
                    .ignoresSafeArea()
            }
        }
        .task { await runPipeline() }
        .onAppear  {
            appState.isReadingArticle = true
            appearedAt = Date()

            // Phase 2d — track return visit if article was already read
            if article.isRead {
                AffinityTracker.shared.record(
                    .returnVisit,
                    sourceID: article.sourceID,
                    itemID: article.id
                )
            }
        }
        // Only clear the flag when we're truly leaving the reader, not when
        // a sheet slides in on top of us.
        .onDisappear {
            if !showPaywallSafari && !showChatSheet {
                appState.isReadingArticle = false

                // Phase 2d — Dwell time tracking
                if let appeared = appearedAt {
                    let dwell = Date().timeIntervalSince(appeared)
                    let eventType: InteractionEventType = dwell < 5 ? .quickBounce
                                                        : dwell < 15 ? .articleOpen
                                                        : dwell < 45 ? .dwellMedium
                                                        : .dwellLong
                    AffinityTracker.shared.record(
                        eventType,
                        sourceID: article.sourceID,
                        itemID: article.id,
                        dwellTime: dwell
                    )
                }
            }
        }
    }

    // MARK: - Pipeline

    @MainActor
    private func runPipeline() async {
        guard let url = URL(string: article.articleURL) else {
            loadState = .failed("The article link is invalid.")
            return
        }

        // YouTube content: skip the pipeline and show the appropriate card.
        if YouTubeService.isYouTubeURL(url) {
            let urlString = url.absoluteString
            if YouTubeService.isYouTubeVideoOrShortURL(urlString) {
                loadState = .youtube(url)
                return
            }
            if urlString.contains("list=") {
                loadState = .playlist(url)
                return
            }
        }

        // Non-YouTube video URLs (Vimeo, direct .mp4 / .mov / .m4v / .webm).
        if let kind = VideoDetector.detect(url) {
            loadState = .video(url, kind)
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
            var extracted = try await pipeline.process(item: item)

            // If the pipeline found no hero image, fall back to the RSS image URL
            // that was already fetched for the Today card (avoids showing nothing).
            if extracted.heroImageURL == nil,
               let rssImageURL = article.imageURL.flatMap({ URL(string: $0) }) {
                extracted = ExtractedArticle(
                    id:           extracted.id,
                    sourceURL:    extracted.sourceURL,
                    title:        extracted.title,
                    author:       extracted.author,
                    publishDate:  extracted.publishDate,
                    heroImageURL: rssImageURL,
                    feedName:     extracted.feedName,
                    nodes:        extracted.nodes,
                    cachedAt:     extracted.cachedAt
                )
            }

            // Post-pipeline paywall detection — fires once per article.
            // markArticlePaywalled flips the in-memory flag and persists to
            // ArticleState so the badge in ArticleCardView lights up automatically.
            if !article.isPaywalled,
               PaywallDetector.isPaywalled(article: extracted) {
                SwiftDataService.shared.markArticlePaywalled(id: article.id)
            }

            loadState = .loaded(extracted)
            chatViewModel.setArticleContext(
                title: extracted.title,
                feedName: extracted.feedName,
                nodes: extracted.nodes
            )
        } catch {
            guard !Task.isCancelled else { return }
            loadState = .failed(error.localizedDescription)
        }
    }

    // MARK: - Chat Bubble

    private var chatBubbleButton: some View {
        Button {
            showChatSheet = true
        } label: {
            Image(systemName: "sparkles")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 50, height: 50)
                .background(
                    Circle()
                        .fill(Design.Colors.primary)
                        .shadow(color: .black.opacity(0.18), radius: 8, x: 0, y: 3)
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Loading View

    private var loadingView: some View {
        ArticleSkeletonView()
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

                AsyncImage(url: thumbURL) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    default:
                        ZStack {
                            Color(.secondarySystemBackground)
                            Image(systemName: "play.rectangle.fill")
                                .font(.system(size: 48, weight: .ultraLight))
                                .foregroundStyle(.secondary)
                        }
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

    // MARK: - Non-YouTube Video View

    @MainActor
    private func videoView(videoURL: URL, kind: VideoDetector.VideoKind) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {

                // ── Media header ───────────────────────────────────────
                switch kind {
                case .directFile:
                    VideoPlayer(player: AVPlayer(url: videoURL))
                        .frame(maxWidth: .infinity)
                        .frame(height: 210)

                case .vimeo(let id):
                    VimeoThumbnailView(vimeoID: id)
                        .frame(maxWidth: .infinity)
                        .frame(height: 210)
                        .clipped()
                }

                // ── Title & Source ─────────────────────────────────────
                VStack(alignment: .leading, spacing: 6) {
                    Text(article.title)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 6) {
                        Image(systemName: "play.circle")
                            .font(.system(size: 13))
                            .foregroundStyle(.blue)
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
                            .foregroundStyle(.blue)
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
                    let actionLabel: String = {
                        if case .vimeo = kind { return "Watch on Vimeo" }
                        return "Open Video"
                    }()

                    Link(destination: videoURL) {
                        HStack(spacing: 8) {
                            Image(systemName: "play.circle.fill")
                                .font(.system(size: 18))
                            Text(actionLabel)
                                .font(.system(size: 16, weight: .semibold))
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.blue, in: RoundedRectangle(cornerRadius: 12))
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
}

// MARK: - VimeoThumbnailView

/// Async thumbnail for a Vimeo video using the public oEmbed API.
/// Falls back to a generic video icon while loading or on failure.
private struct VimeoThumbnailView: View {

    let vimeoID: String
    @State private var thumbURL: URL?

    var body: some View {
        ZStack {
            Color(.secondarySystemBackground)

            if let thumbURL {
                AsyncImage(url: thumbURL) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    default:
                        genericIcon
                    }
                }
            } else {
                genericIcon
            }
        }
        .task {
            thumbURL = await VideoDetector.vimeoThumbnailURL(for: vimeoID)
        }
    }

    private var genericIcon: some View {
        Image(systemName: "film")
            .font(.system(size: 48, weight: .ultraLight))
            .foregroundStyle(.secondary)
    }
}

