//
//  CachedImageView.swift
//  OpenRSS
//
//  Drop-in AsyncImage replacement that downsamples images during decode
//  so only display-sized bitmaps are held in memory.
//

import SwiftUI
import UIKit

/// A memory-efficient async image view that downsamples source images to the
/// requested point size before caching them.  Uses `NSCache` so the system can
/// evict entries automatically under memory pressure.
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
            } else if failed {
                placeholder()
            } else {
                placeholder()
                    .overlay(ProgressView().tint(.white.opacity(0.5)))
            }
        }
        .task(id: url) {
            guard let url else { failed = true; return }
            if let cached = ImageDownsampler.shared.cached(for: url) {
                image = cached
                return
            }
            do {
                let downloaded = try await ImageDownsampler.shared.downsample(
                    url: url,
                    pointSize: pointSize
                )
                image = downloaded
            } catch {
                failed = true
            }
        }
    }
}

// MARK: - Downsampler + Cache

private final class ImageDownsampler {

    static let shared = ImageDownsampler()

    private let cache = NSCache<NSURL, UIImage>()
    private let session: URLSession

    private init() {
        cache.countLimit = 80
        cache.totalCostLimit = 40 * 1024 * 1024  // ~40 MB of decoded thumbnails
        session = .shared
    }

    func cached(for url: URL) -> UIImage? {
        cache.object(forKey: url as NSURL)
    }

    func downsample(url: URL, pointSize: CGSize) async throws -> UIImage {
        if let hit = cache.object(forKey: url as NSURL) { return hit }

        let (data, _) = try await session.data(from: url)

        let scale = await UIScreen.main.scale
        let maxPixel = max(pointSize.width, pointSize.height) * scale

        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            throw URLError(.cannotDecodeContentData)
        }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel
        ]

        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw URLError(.cannotDecodeContentData)
        }

        let result = UIImage(cgImage: cgImage)
        let cost = cgImage.bytesPerRow * cgImage.height
        cache.setObject(result, forKey: url as NSURL, cost: cost)
        return result
    }
}
