//
//  ThumbnailService.swift
//  OpenRSS
//
//  Persistent, downsampled image cache for hero images shown in river cards.
//  Backed by NSCache (in-memory decoded UIImages) + on-disk JPEGs in
//  Caches/thumbnails/<sha256(url)>.jpg.
//
//  Design:
//    • Actor — all state is actor-isolated, no locks needed.
//    • NSCache for in-memory decoded bitmaps (~40 MB cap; system can also
//      evict under memory pressure).
//    • On-disk JPEG cache in the system Caches directory so iOS can evict
//      the whole folder under storage pressure if our LRU sweep doesn't
//      run first. JPEGs are ~30–80 KB each at thumbnail resolution.
//    • LRU sweep on init: if total disk usage exceeds maxDiskBytes, delete
//      oldest entries (by modification date) until we're back under cap.
//    • inFlight task table coalesces concurrent warms for the same URL so
//      we never download the same image twice in parallel.
//    • warm(...) is the prefetch entry point — never throws, safe to call
//      fire-and-forget from BG refresh / processing tasks.
//

import Foundation
import UIKit
import CryptoKit

// MARK: - ThumbnailService

actor ThumbnailService {

    // MARK: - Singleton

    static let shared = ThumbnailService()

    // MARK: - Caps

    /// In-memory: ~40 MB of decoded bitmaps; ~120 entries (LRU via NSCache).
    private static let memoryCostLimit = 40 * 1024 * 1024
    private static let memoryCountLimit = 120

    /// On-disk: ~200 MB of JPEGs. Sweep on init if exceeded.
    private static let maxDiskBytes: Int = 200 * 1024 * 1024

    /// JPEG compression — 0.7 keeps recognizable quality at thumbnail sizes.
    private static let jpegCompression: CGFloat = 0.7

    /// Browser-like UA — some CDNs reject non-browser fetches with 403.
    private static let userAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"

    // MARK: - State

    private let cache = NSCache<NSURL, UIImage>()
    private let diskDir: URL
    private let session: URLSession = .shared

    /// Coalesces concurrent fetches for the same URL.
    private var inFlight: [URL: Task<UIImage?, Never>] = [:]

    // MARK: - Init

    private init() {
        cache.totalCostLimit = Self.memoryCostLimit
        cache.countLimit = Self.memoryCountLimit

        let caches = FileManager.default
            .urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        diskDir = caches.appendingPathComponent("thumbnails", isDirectory: true)
        try? FileManager.default.createDirectory(
            at: diskDir, withIntermediateDirectories: true
        )

        // LRU sweep runs detached so init returns immediately.
        let dirCopy = diskDir
        Task.detached(priority: .background) {
            await Self.sweepLRU(diskDir: dirCopy, maxBytes: Self.maxDiskBytes)
        }
    }

    // MARK: - Public API

    /// Returns a cached + downsampled image for `url`, or nil if not cached.
    /// Checks NSCache first, then promotes a disk hit back into memory.
    /// Pure read — never triggers a network fetch.
    func cachedImage(for url: URL) -> UIImage? {
        if let mem = cache.object(forKey: url as NSURL) {
            return mem
        }
        let path = diskPath(for: url)
        guard FileManager.default.fileExists(atPath: path.path),
              let data = try? Data(contentsOf: path),
              let image = UIImage(data: data) else { return nil }
        cache.setObject(image, forKey: url as NSURL, cost: estimatedCost(of: image))
        return image
    }

    /// Returns the cached image, or downloads + downsamples + persists it.
    /// Throws on network or decode error so callers can fall back to a placeholder.
    func thumbnail(for url: URL, pointSize: CGSize) async throws -> UIImage {
        if let hit = cachedImage(for: url) { return hit }

        if let existing = inFlight[url] {
            if let img = await existing.value { return img }
            throw URLError(.cannotDecodeContentData)
        }

        let task = Task<UIImage?, Never> { [weak self] in
            guard let self else { return nil }
            return try? await self.fetchAndStore(url: url, pointSize: pointSize)
        }
        inFlight[url] = task
        defer { inFlight.removeValue(forKey: url) }

        if let img = await task.value { return img }
        throw URLError(.cannotDecodeContentData)
    }

    /// Fire-and-forget pre-fetch. Never throws. Safe to call from background tasks.
    /// Concurrent calls for the same URL are coalesced.
    func warm(url: URL, pointSize: CGSize) async {
        if cachedImage(for: url) != nil { return }

        if let existing = inFlight[url] {
            _ = await existing.value
            return
        }

        let task = Task<UIImage?, Never> { [weak self] in
            guard let self else { return nil }
            return try? await self.fetchAndStore(url: url, pointSize: pointSize)
        }
        inFlight[url] = task
        _ = await task.value
        inFlight.removeValue(forKey: url)
    }

    /// True when a thumbnail for `url` is already on disk or in memory.
    /// Useful for the BGProcessingTask to skip already-warmed items.
    func hasThumbnail(for url: URL) -> Bool {
        if cache.object(forKey: url as NSURL) != nil { return true }
        return FileManager.default.fileExists(atPath: diskPath(for: url).path)
    }

    // MARK: - Internals

    private func fetchAndStore(url: URL, pointSize: CGSize) async throws -> UIImage {
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)

        if let http = response as? HTTPURLResponse,
           !(200...299).contains(http.statusCode) {
            throw URLError(.badServerResponse)
        }

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

        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(
            source, 0, options as CFDictionary
        ) else {
            throw URLError(.cannotDecodeContentData)
        }

        let image = UIImage(cgImage: cgImage)
        cache.setObject(image, forKey: url as NSURL, cost: cgImage.bytesPerRow * cgImage.height)

        // Persist to disk for next-launch hits. Best-effort; ignore write errors.
        if let jpeg = image.jpegData(compressionQuality: Self.jpegCompression) {
            try? jpeg.write(to: diskPath(for: url), options: .atomic)
        }

        return image
    }

    private func diskPath(for url: URL) -> URL {
        let digest = SHA256.hash(data: Data(url.absoluteString.utf8))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return diskDir.appendingPathComponent("\(hex).jpg")
    }

    private func estimatedCost(of image: UIImage) -> Int {
        guard let cg = image.cgImage else {
            return Int(image.size.width * image.size.height * 4)
        }
        return cg.bytesPerRow * cg.height
    }

    // MARK: - LRU Sweep

    /// Static so it can run from a detached Task without keeping the actor alive.
    /// Reads file modification dates and total size; if over budget, deletes
    /// oldest files until we're back under `maxBytes`.
    private static func sweepLRU(diskDir: URL, maxBytes: Int) async {
        let fm = FileManager.default
        guard let urls = try? fm.contentsOfDirectory(
            at: diskDir,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        var entries: [(url: URL, mtime: Date, size: Int)] = []
        entries.reserveCapacity(urls.count)

        for url in urls {
            guard let values = try? url.resourceValues(
                forKeys: [.contentModificationDateKey, .fileSizeKey]
            ),
            let mtime = values.contentModificationDate,
            let size = values.fileSize else { continue }
            entries.append((url, mtime, size))
        }

        var total = entries.reduce(0) { $0 + $1.size }
        guard total > maxBytes else { return }

        // Delete oldest first until under budget.
        entries.sort { $0.mtime < $1.mtime }
        for entry in entries where total > maxBytes {
            try? fm.removeItem(at: entry.url)
            total -= entry.size
        }
    }
}
