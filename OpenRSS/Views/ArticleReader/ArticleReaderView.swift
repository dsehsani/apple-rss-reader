//
//  ArticleReaderView.swift
//  OpenRSS
//
//  Phase 5 — Template Rendering
//
//  Main reader view.  Accepts a fully-processed ExtractedArticle and renders
//  a header zone, a scrollable body zone, and a footer zone.
//

import SwiftUI

// MARK: - Summary State

private enum SummaryState {
    case idle
    case loading
    case result(String)
    case tooShort
    case error(String)
}

// MARK: - ArticleReaderView

struct ArticleReaderView: View {

    let extracted: ExtractedArticle
    /// Audio enclosure URL from the RSS feed. When non-nil an inline player is
    /// shown below the hero image. Nil for articles without audio.
    var audioURL: URL? = nil
    /// Non-nil for video articles. The hero image becomes a tappable play button
    /// that opens this URL in SFSafariViewController.
    var videoURL: URL? = nil
    var onSignIn: (() -> Void)? = nil

    @State private var summaryState: SummaryState = .idle
    @State private var showSummarySheet = false
    @State private var showVideoSafari = false

    // MARK: - Body

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                headerZone
                    .padding(.bottom, 24)

                bodyZone
                    .padding(.horizontal, 20)

                footerZone
                    .padding(.top, 32)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 8)

                paywallFootnote
                    .padding(.horizontal, 20)
                    .padding(.bottom, 40)
            }
            // containerRelativeFrame(.horizontal) anchors the content width to the
            // scroll view's actual bounds width. Unlike frame(maxWidth: .infinity),
            // this prevents SwiftUI from ever reporting a wider ideal size to the
            // underlying UIScrollView — so contentSize.width stays == bounds.width
            // and UIKit never sets a non-zero contentOffset.x that clips the left edge.
            .containerRelativeFrame(.horizontal, alignment: .leading)
            .clipped()
        }
        .background(Color(.systemBackground))
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showSummarySheet) {
            SummarySheetView(state: summaryState)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(20)
        }
        .sheet(isPresented: $showVideoSafari) {
            if let url = videoURL {
                SafariView(url: url).ignoresSafeArea()
            }
        }
    }

    // MARK: - Header Zone

    private var headerZone: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Hero image — tappable play button overlay when article is a video
            if let heroURL = extracted.heroImageURL {
                CachedImageView(
                    url: heroURL,
                    pointSize: CGSize(width: 400, height: 220),
                    contentMode: .fill
                ) {
                    Rectangle().fill(Color(.secondarySystemFill))
                }
                .frame(maxWidth: .infinity)
                .frame(height: 220)
                .clipped()
                .overlay {
                    if videoURL != nil {
                        Button { showVideoSafari = true } label: {
                            ZStack {
                                // Full-image tap target
                                Color.clear
                                // Centered play circle
                                ZStack {
                                    Circle()
                                        .fill(.black.opacity(0.45))
                                        .frame(width: 60, height: 60)
                                    Image(systemName: "play.fill")
                                        .font(.system(size: 22, weight: .semibold))
                                        .foregroundStyle(.white)
                                        .offset(x: 2)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.bottom, 20)
            }

            // Audio player — only shown when the RSS item carried an audio enclosure.
            if let audioURL {
                AudioPlayerView(audioURL: audioURL)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
            }

            VStack(alignment: .leading, spacing: 8) {
                // Feed name
                Text(extracted.feedName)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .tracking(0.8)
                    .frame(maxWidth: .infinity, alignment: .leading)

                // Title — fixedSize before frame so the frame sees the capped width
                Text(extracted.title)
                    .font(.title2)
                    .fontWeight(.bold)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)

                // Byline + read time
                HStack(spacing: 12) {
                    if let author = extracted.author, !author.isEmpty {
                        Text(author)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Text(estimatedReadTime)
                        .font(.subheadline)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // Summarize pill button
                summarizeButton
                    .padding(.top, 2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
        }
    }

    // MARK: - Summarize Button

    private var isSummarizing: Bool {
        if case .loading = summaryState { return true }
        return false
    }

    private var summarizeButton: some View {
        Button {
            Task { await summarize() }
        } label: {
            HStack(spacing: 5) {
                if isSummarizing {
                    ProgressView()
                        .scaleEffect(0.7)
                        .tint(Design.Colors.primary)
                } else {
                    Image(systemName: "sparkles")
                        .font(.system(size: 11, weight: .semibold))
                }
                Text("Summarize")
                    .font(.system(size: 13, weight: .semibold))
            }
            .foregroundStyle(Design.Colors.primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Design.Colors.primary.opacity(0.10), in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(isSummarizing)
    }

    // MARK: - Summarize Action

    @MainActor
    private func summarize() async {
        switch summaryState {
        case .loading:
            return
        case .result, .tooShort:
            showSummarySheet = true
            return
        case .idle, .error:
            break
        }

        guard articleWordCount >= 50 else {
            summaryState = .tooShort
            showSummarySheet = true
            return
        }

        summaryState = .loading
        showSummarySheet = true

        let text = String(articlePlainText().prefix(3000))
        let prompt = """
        Summarize the following article in exactly 3 concise sentences. \
        Focus on the key facts and main takeaway. Plain text only.

        Title: \(extracted.title)

        Content:
        \(text)
        """

        do {
            let result = try await GeminiService.send(
                history: [ChatMessage(role: .user, content: prompt)],
                articleContext: nil
            )
            summaryState = .result(result.trimmingCharacters(in: .whitespacesAndNewlines))
        } catch {
            summaryState = .error(error.localizedDescription)
        }
    }

    // MARK: - Body Zone

    /// Strips query parameters and URL fragments so CDN size variants of the
    /// same image (e.g. ?width=1200 vs ?width=400) compare as equal.
    private func normalizedImageKey(_ url: URL) -> String {
        var c = URLComponents(url: url, resolvingAgainstBaseURL: false)
        c?.queryItems = nil
        c?.fragment = nil
        return c?.url?.absoluteString ?? url.absoluteString
    }

    private var bodyZone: some View {
        // Remove any .image node whose normalized URL matches the hero already
        // shown in the header zone. Handles both freshly-extracted articles and
        // cached articles stored before the pipeline-level dedup was introduced,
        // and catches feeds (e.g. The Atlantic, NPR podcasts) where the first
        // body image is the same as the og:image hero.
        let heroKey = extracted.heroImageURL.map { normalizedImageKey($0) }
        let displayNodes = extracted.nodes.filter { node in
            guard case .image(let url, _) = node else { return true }
            guard let key = heroKey else { return true }
            return normalizedImageKey(url) != key
        }
        // VStack (not LazyVStack) gives consistent width proposals to children.
        // LazyVStack has known layout quirks with fixedSize in scroll views,
        // causing children to report unconstrained widths that push the whole
        // container beyond screen width and shift the header text off the left edge.
        return VStack(alignment: .leading, spacing: 16) {
            ForEach(Array(displayNodes.enumerated()), id: \.offset) { _, node in
                nodeView(for: node)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func nodeView(for node: ContentNode) -> some View {
        switch node {
        case .heading(let level, let text):
            HeadingView(level: level, text: text)

        case .paragraph(let text):
            ParagraphView(text: text)

        case .image(let url, let caption):
            ArticleImageView(url: url, caption: caption)

        case .blockquote(let text):
            BlockquoteView(text: text)

        case .list(let items, let ordered):
            ListItemsView(items: items, ordered: ordered)

        case .codeBlock(let text):
            CodeBlockView(text: text)

        case .table(let headers, let rows):
            TableView(headers: headers, rows: rows)

        case .videoEmbed(let url, let thumbnailURL):
            VideoEmbedView(url: url, thumbnailURL: thumbnailURL)
        }
    }

    // MARK: - Paywall Footnote

    private var paywallFootnote: some View {
        Button {
            onSignIn?()
        } label: {
            (Text("Hitting a paywall?  ") + Text("Sign in here").underline())
                .font(.footnote)
                .foregroundStyle(Color(.tertiaryLabel))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Footer Zone

    private var footerZone: some View {
        HStack(spacing: 16) {
            Link(destination: extracted.sourceURL) {
                Label("Open in Safari", systemImage: "safari")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(Color.accentColor, in: Capsule())
            }

            ShareLink(item: extracted.sourceURL) {
                Label("Share", systemImage: "square.and.arrow.up")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(
                        Capsule()
                            .fill(Color(.secondarySystemFill))
                    )
            }
        }
    }

    // MARK: - Helpers

    private var articleWordCount: Int {
        extracted.nodes.reduce(0) { acc, node in
            switch node {
            case .paragraph(let t), .blockquote(let t), .codeBlock(let t):
                return acc + t.split(separator: " ").count
            case .heading(_, let t):
                return acc + t.split(separator: " ").count
            case .list(let items, _):
                return acc + items.joined(separator: " ").split(separator: " ").count
            case .image, .videoEmbed:
                return acc
            case .table(let headers, let rows):
                let allText = (headers + rows.flatMap { $0 }).joined(separator: " ")
                return acc + allText.split(separator: " ").count
            }
        }
    }

    private func articlePlainText() -> String {
        extracted.nodes.compactMap { node -> String? in
            switch node {
            case .heading(_, let t):   return t
            case .paragraph(let t):    return t
            case .blockquote(let t):   return t
            case .codeBlock(let t):    return t
            case .list(let items, _):  return items.joined(separator: " ")
            case .table(let h, let r): return (h + r.flatMap { $0 }).joined(separator: " ")
            case .image, .videoEmbed:  return nil
            }
        }.joined(separator: "\n\n")
    }

    private var estimatedReadTime: String {
        let wordCount = extracted.nodes.reduce(0) { acc, node in
            switch node {
            case .paragraph(let t), .blockquote(let t), .codeBlock(let t):
                return acc + t.split(separator: " ").count
            case .heading(_, let t):
                return acc + t.split(separator: " ").count
            case .list(let items, _):
                return acc + items.joined(separator: " ").split(separator: " ").count
            case .image, .videoEmbed:
                return acc
            case .table(let headers, let rows):
                let allText = (headers + rows.flatMap { $0 }).joined(separator: " ")
                return acc + allText.split(separator: " ").count
            }
        }
        let minutes = max(1, wordCount / 200)
        return "\(minutes) min read"
    }
}

// MARK: - Summary Sheet View

private struct SummarySheetView: View {

    let state: SummaryState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header row
            HStack {
                Label("Summary", systemImage: "sparkles")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.primary)
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(8)
                        .background(Color(.secondarySystemFill), in: Circle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 16)

            Divider()

            contentView
        }
        .background(Color(.systemBackground))
    }

    @ViewBuilder
    private var contentView: some View {
        switch state {
        case .idle:
            EmptyView()

        case .loading:
            VStack(spacing: 12) {
                ProgressView()
                    .scaleEffect(1.2)
                Text("Generating summary…")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

        case .result(let text):
            ScrollView {
                Text(text)
                    .font(.system(size: 16))
                    .foregroundStyle(.primary)
                    .lineSpacing(6)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

        case .tooShort:
            VStack(spacing: 10) {
                Image(systemName: "doc.text")
                    .font(.system(size: 34, weight: .ultraLight))
                    .foregroundStyle(.secondary)
                Text("This article is too short to summarize.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 32)

        case .error(let message):
            VStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 30, weight: .ultraLight))
                    .foregroundStyle(.orange)
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 32)
        }
    }
}
