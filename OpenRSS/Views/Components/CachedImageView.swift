//
//  CachedImageView.swift
//  OpenRSS
//
//  SwiftUI wrapper around ThumbnailService.
//  Drop-in AsyncImage replacement that downsamples images during decode and
//  persists thumbnails to disk so cards re-appear instantly across launches.
//

import SwiftUI
import UIKit

/// Memory-efficient async image view backed by `ThumbnailService`.
/// Synchronous in-memory cache hits paint immediately; cold loads await the
/// downsample + disk write before swapping the placeholder for the image.
struct CachedImageView<Placeholder: View>: View {

    let url: URL?
    let pointSize: CGSize
    let contentMode: ContentMode
    @ViewBuilder let placeholder: () -> Placeholder

    @State private var image: UIImage?
    @State private var failed = false

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
                    .transition(.opacity)
            } else if failed {
                placeholder()
            } else {
                placeholder()
            }
        }
        .task(id: url) {
            guard let url else { failed = true; return }
            // Reset across URL changes (e.g. card re-bound to a different article).
            image = nil
            failed = false

            // Cache hit: paints in this run-loop tick.
            if let cached = await ThumbnailService.shared.cachedImage(for: url) {
                image = cached
                return
            }
            do {
                let downloaded = try await ThumbnailService.shared.thumbnail(
                    for: url, pointSize: pointSize
                )
                if !Task.isCancelled {
                    withAnimation(.easeOut(duration: 0.18)) {
                        image = downloaded
                    }
                }
            } catch {
                if !Task.isCancelled {
                    failed = true
                }
            }
        }
    }
}
