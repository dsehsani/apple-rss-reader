//
//  HeroPrefetcher.swift
//  OpenRSS
//
//  Bounded, time-budgeted hero-image pre-fetch helper used by:
//    • RiverViewModel snapshot post-step (foreground, top-30)
//    • OpenRSSApp BGAppRefreshTask handler (background, top-10)
//    • OpenRSSApp BGProcessingTask handler (overnight, items 11..50)
//
//  For each input it:
//    1. Resolves the og:image URL via OGImageService if the input is an
//       article page rather than a direct image URL.
//    2. Calls ThumbnailService.shared.warm(...) so the downsampled JPEG
//       lands on disk before the user (or system) needs it.
//
//  Concurrency is bounded so we don't hammer external hosts. A wall-clock
//  budget bounds total runtime so background tasks never expire mid-write.
//

import Foundation
import CoreGraphics

// MARK: - HeroInput

/// One unit of work for the prefetcher.
/// `pageURL` is the article page (used for og:image lookup when needed).
/// `imageURL` is the already-resolved image URL when the feed provided one.
nonisolated struct HeroInput: Sendable {
    let pageURL: String
    let imageURL: String?

    /// `nonisolated` so it can be used as a default value in nonisolated
    /// function signatures even though the project defaults to MainActor.
    nonisolated static let defaultHeroPointSize = CGSize(width: 400, height: 180)
}

// MARK: - HeroPrefetcher

nonisolated enum HeroPrefetcher {

    /// Maximum concurrent network operations. Higher than 4 risks rate limits
    /// from popular CDNs (e.g. Cloudflare for HN-linked articles).
    nonisolated static let defaultConcurrency = 4

    /// Warms hero thumbnails for the given inputs.
    ///
    /// - Parameters:
    ///   - inputs: Page+image URL pairs to warm.
    ///   - pointSize: Render target size for downsampling (default 400×180).
    ///   - concurrency: Max in-flight network operations.
    ///   - budgetSeconds: Wall-clock cap for the whole batch. After this
    ///     elapses, no new tasks start; in-flight ones finish naturally.
    static func warm(
        inputs: [HeroInput],
        pointSize: CGSize = HeroInput.defaultHeroPointSize,
        concurrency: Int = defaultConcurrency,
        budgetSeconds: TimeInterval
    ) async {
        guard !inputs.isEmpty, budgetSeconds > 0 else { return }

        let deadline = Date().addingTimeInterval(budgetSeconds)

        await withTaskGroup(of: Void.self) { group in
            var iterator = inputs.makeIterator()
            var inFlight = 0

            // Seed the group with up to `concurrency` initial tasks.
            for _ in 0..<concurrency {
                guard Date() < deadline, let input = iterator.next() else { break }
                group.addTask { await processOne(input, pointSize: pointSize) }
                inFlight += 1
            }

            // As each task finishes, start another until we run out or hit the deadline.
            while inFlight > 0 {
                _ = await group.next()
                inFlight -= 1

                guard Date() < deadline, let next = iterator.next() else { continue }
                group.addTask { await processOne(next, pointSize: pointSize) }
                inFlight += 1
            }
        }
    }

    /// Convenience — accepts plain URL strings (used by BG tasks where we
    /// already know which item is the canonical for each cluster).
    static func warm(
        urls: [String],
        pointSize: CGSize = HeroInput.defaultHeroPointSize,
        concurrency: Int = defaultConcurrency,
        budgetSeconds: TimeInterval
    ) async {
        let inputs = urls.map { HeroInput(pageURL: $0, imageURL: nil) }
        await warm(
            inputs: inputs,
            pointSize: pointSize,
            concurrency: concurrency,
            budgetSeconds: budgetSeconds
        )
    }

    // MARK: - Private

    /// Resolves the og:image URL if needed, then warms the thumbnail.
    /// Silent on every error — this is best-effort prefetch.
    private static func processOne(_ input: HeroInput, pointSize: CGSize) async {
        let resolvedString: String?
        if let direct = input.imageURL, !direct.isEmpty {
            resolvedString = direct
        } else {
            // Use OGImageService — its negative cache and dedup keep this cheap.
            if let cached = await OGImageService.shared.cachedImageURL(for: input.pageURL) {
                resolvedString = cached
            } else {
                await OGImageService.shared.prefetch(articleURL: input.pageURL)
                resolvedString = await OGImageService.shared.cachedImageURL(for: input.pageURL)
            }
        }

        guard let str = resolvedString, let url = URL(string: str) else { return }
        if await ThumbnailService.shared.hasThumbnail(for: url) { return }
        await ThumbnailService.shared.warm(url: url, pointSize: pointSize)
    }
}
