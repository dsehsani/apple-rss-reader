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
            CachedImageView(
                url: url,
                pointSize: CGSize(width: 400, height: 300),
                contentMode: .fit
            ) {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(.secondarySystemFill))
                    .frame(height: 180)
            }
            // Explicit width cap prevents the image from reporting a wider
            // intrinsic size during async loading, which would temporarily
            // inflate UIScrollView.contentSize.width and shift contentOffset.x,
            // causing the left edge of all content to clip off-screen.
            .frame(maxWidth: .infinity)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: 10))

            if let caption, !caption.isEmpty {
                Text(caption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .italic()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4)
            }
        }
        .frame(maxWidth: .infinity)
        .clipped()
        .padding(.vertical, 4)
    }
}
