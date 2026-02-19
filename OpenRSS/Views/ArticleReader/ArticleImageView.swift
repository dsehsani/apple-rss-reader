//
//  ArticleImageView.swift
//  OpenRSS
//
//  Phase 5 — renders an image ContentNode with async loading and optional caption.
//

import SwiftUI

struct ArticleImageView: View {

    let url: URL
    let caption: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: 10))

                case .failure:
                    // Silently skip broken images
                    EmptyView()

                case .empty:
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color(.secondarySystemFill))
                        .frame(height: 180)
                        .overlay(
                            ProgressView()
                        )

                @unknown default:
                    EmptyView()
                }
            }

            if let caption, !caption.isEmpty {
                Text(caption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .italic()
                    .padding(.horizontal, 4)
            }
        }
        .padding(.vertical, 4)
    }
}
