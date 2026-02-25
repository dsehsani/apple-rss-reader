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

// MARK: - ArticleReaderView

struct ArticleReaderView: View {

    let extracted: ExtractedArticle

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
                    .padding(.bottom, 40)
            }
        }
        .background(Color(.systemBackground))
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Header Zone

    private var headerZone: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Hero image
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

                // Title
                Text(extracted.title)
                    .font(.title2)
                    .fontWeight(.bold)
                    .fixedSize(horizontal: false, vertical: true)

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
            }
            .padding(.horizontal, 20)
        }
    }

    // MARK: - Body Zone

    private var bodyZone: some View {
        LazyVStack(alignment: .leading, spacing: 16) {
            ForEach(Array(extracted.nodes.enumerated()), id: \.offset) { _, node in
                nodeView(for: node)
            }
        }
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
        }
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

    private var estimatedReadTime: String {
        let wordCount = extracted.nodes.reduce(0) { acc, node in
            switch node {
            case .paragraph(let t), .blockquote(let t), .codeBlock(let t):
                return acc + t.split(separator: " ").count
            case .heading(_, let t):
                return acc + t.split(separator: " ").count
            case .list(let items, _):
                return acc + items.joined(separator: " ").split(separator: " ").count
            case .image:
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
