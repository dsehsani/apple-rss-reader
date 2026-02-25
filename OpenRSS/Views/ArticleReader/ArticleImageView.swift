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
            .clipShape(RoundedRectangle(cornerRadius: 10))

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
