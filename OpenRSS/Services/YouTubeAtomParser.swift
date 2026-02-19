//
//  YouTubeAtomParser.swift
//  OpenRSS
//
//  Lightweight SAX parser for YouTube Atom feeds.
//
//  FeedKit's AtomPath does not map /feed/entry/media:group/media:description
//  or /feed/entry/media:group/media:thumbnail, so these two fields are always
//  nil for YouTube when using FeedKit alone.
//
//  This parser walks the raw XML once and returns a lookup table:
//    [videoWatchURL: VideoMeta(thumbnailURL:, description:)]
//
//  Usage (inside SwiftDataService.refreshAllFeeds):
//    let extras = YouTubeAtomParser().parse(data: rawData)
//    let thumbURL = extras[articleURL]?.thumbnailURL
//    let desc     = extras[articleURL]?.description
//

import Foundation

// MARK: - YouTubeAtomParser

final class YouTubeAtomParser: NSObject, XMLParserDelegate {

    // MARK: - Output

    struct VideoMeta {
        var thumbnailURL: String?
        var description:  String?
    }

    // MARK: - State

    private var results: [String: VideoMeta] = [:]
    private var currentVideoURL: String?
    private var currentMeta     = VideoMeta()
    private var inMediaGroup    = false
    private var captureText     = false
    private var charBuffer      = ""

    // MARK: - Public API

    /// Parses a YouTube Atom feed and returns per-video metadata keyed by watch URL.
    func parse(data: Data) -> [String: VideoMeta] {
        results = [:]
        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.parse()
        return results
    }

    // MARK: - XMLParserDelegate

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes: [String: String] = [:]
    ) {
        switch elementName {

        case "entry":
            // Reset per-entry state
            currentVideoURL = nil
            currentMeta     = VideoMeta()

        case "media:group":
            inMediaGroup = true

        case "link":
            // <link rel="alternate" href="https://www.youtube.com/watch?v=…"/>
            if attributes["rel"] == "alternate", let href = attributes["href"] {
                currentVideoURL = href
            }

        case "media:thumbnail" where inMediaGroup:
            if let url = attributes["url"] {
                currentMeta.thumbnailURL = url
            }

        case "media:description" where inMediaGroup:
            captureText = true
            charBuffer  = ""

        default:
            break
        }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        switch elementName {

        case "entry":
            if let url = currentVideoURL {
                results[url] = currentMeta
            }

        case "media:group":
            inMediaGroup = false

        case "media:description":
            if captureText {
                currentMeta.description = charBuffer
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                captureText = false
            }

        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if captureText {
            charBuffer += string
        }
    }
}
