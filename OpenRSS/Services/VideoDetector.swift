//
//  VideoDetector.swift
//  OpenRSS
//
//  Detects non-YouTube embedded video URLs:
//    - Vimeo watch pages (vimeo.com/<id>, player.vimeo.com/video/<id>)
//    - Direct video files (.mp4, .m4v, .mov, .webm)
//
//  YouTube URLs are intentionally excluded — those are handled by YouTubeService.
//

import Foundation

// MARK: - VideoDetector

enum VideoDetector {

    // MARK: - Video Kind

    /// Describes the type of non-YouTube video that was detected.
    enum VideoKind: Equatable {
        /// A Vimeo video identified by its numeric ID.
        case vimeo(id: String)
        /// A directly-accessible video file (mp4 / m4v / mov / webm).
        case directFile(URL)
    }

    // MARK: - Detection

    /// Returns the `VideoKind` for `url`, or `nil` if the URL is not a recognised
    /// non-YouTube video.
    static func detect(_ url: URL) -> VideoKind? {
        // Vimeo check must come first so player.vimeo.com URLs aren't mistaken for
        // generic video files.
        if let id = vimeoID(from: url) {
            return .vimeo(id: id)
        }

        let ext = url.pathExtension.lowercased()
        if ["mp4", "m4v", "mov", "webm"].contains(ext) {
            return .directFile(url)
        }

        return nil
    }

    /// Convenience wrapper that works on a raw URL string.
    static func isVideoURL(_ urlString: String) -> Bool {
        guard let url = URL(string: urlString) else { return false }
        return detect(url) != nil
    }

    // MARK: - Vimeo Thumbnails

    /// Fetches the thumbnail URL for a Vimeo video using the public oEmbed endpoint.
    /// Returns `nil` when the network call fails or the response lacks a thumbnail.
    static func vimeoThumbnailURL(for id: String) async -> URL? {
        guard let encoded = "https://vimeo.com/\(id)"
            .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let oEmbedURL = URL(string: "https://vimeo.com/api/oembed.json?url=\(encoded)")
        else { return nil }

        do {
            let (data, _) = try await URLSession.shared.data(from: oEmbedURL)
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let thumb = json["thumbnail_url"] as? String {
                return URL(string: thumb)
            }
        } catch {
            // Silently swallow — caller falls back to a generic icon.
        }
        return nil
    }

    // MARK: - Private Helpers

    /// Extracts the numeric Vimeo video ID from a URL, or returns `nil`.
    ///
    /// Supported formats:
    ///   - vimeo.com/<id>
    ///   - www.vimeo.com/<id>
    ///   - player.vimeo.com/video/<id>
    private static func vimeoID(from url: URL) -> String? {
        guard let host = url.host?.lowercased() else { return nil }
        guard host == "vimeo.com" || host == "www.vimeo.com" || host == "player.vimeo.com"
        else { return nil }

        let path = url.path
        let components: [String]

        if host == "player.vimeo.com" {
            // /video/<id>
            guard path.hasPrefix("/video/") else { return nil }
            components = path.dropFirst("/video/".count)
                .components(separatedBy: "/")
        } else {
            // /<id>  (optionally with trailing path segments for privacy hash)
            guard path.hasPrefix("/") else { return nil }
            components = path.dropFirst().components(separatedBy: "/")
        }

        guard let rawID = components.first, !rawID.isEmpty,
              rawID.allSatisfy(\.isNumber)
        else { return nil }

        return rawID
    }
}
