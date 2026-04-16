//
//  OPMLService.swift
//  OpenRSS
//
//  OPML 2.0 import and export for feed subscriptions.
//

import Foundation
import SwiftData

// MARK: - Errors

enum OPMLError: LocalizedError {
    case unreadableFile
    case malformedXML
    case noFeedsFound

    var errorDescription: String? {
        switch self {
        case .unreadableFile:  return "The selected file could not be read."
        case .malformedXML:    return "The file is not valid OPML."
        case .noFeedsFound:    return "No feeds were found in this OPML file."
        }
    }
}

// MARK: - OPMLService

final class OPMLService: NSObject {

    static let shared = OPMLService()
    private override init() {}

    // MARK: - Export

    /// Builds an OPML 2.0 file from the user's current folders and feeds.
    /// Unfiled feeds go into a synthetic "Unfiled" group in the output.
    /// Returns a URL to a temp file suitable for passing to a share sheet.
    func export(folders: [FolderModel], unfiledFeeds: [FeedModel]) throws -> URL {
        var xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <opml version="2.0">
          <head>
            <title>OpenRSS Subscriptions</title>
            <dateCreated>\(rfc822Date(Date()))</dateCreated>
          </head>
          <body>\n
        """

        // Folders with their feeds
        for folder in folders.sorted(by: { $0.sortOrder < $1.sortOrder }) {
            let feeds = folder.feeds.sorted(by: { $0.title < $1.title })
            guard !feeds.isEmpty else { continue }

            xml += "    <outline text=\"\(escaped(folder.name))\" title=\"\(escaped(folder.name))\">\n"
            for feed in feeds {
                xml += feedOutline(feed, indent: "      ")
            }
            xml += "    </outline>\n"
        }

        // Unfiled feeds (no parent folder)
        if !unfiledFeeds.isEmpty {
            xml += "    <outline text=\"Unfiled\" title=\"Unfiled\">\n"
            for feed in unfiledFeeds.sorted(by: { $0.title < $1.title }) {
                xml += feedOutline(feed, indent: "      ")
            }
            xml += "    </outline>\n"
        }

        xml += "  </body>\n</opml>"

        // Write to a temp file
        let fileName = "openrss-subscriptions-\(isoDateStamp(Date())).opml"
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        try xml.write(to: tempURL, atomically: true, encoding: .utf8)
        return tempURL
    }

    // MARK: - Import

    /// Parses an OPML file and creates folders + feeds via SwiftDataService.
    /// Skips feeds whose feedURL already exists.
    @MainActor
    func importFromURL(_ url: URL, into service: SwiftDataService) throws -> OPMLImportResult {
        // Resolve security-scoped resource if coming from Files app
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }

        guard let data = try? Data(contentsOf: url) else { throw OPMLError.unreadableFile }

        let parser = OPMLParser(data: data)
        guard let parsed = parser.parse() else { throw OPMLError.malformedXML }
        guard !parsed.isEmpty else { throw OPMLError.noFeedsFound }

        // Build a set of existing feed URLs to skip duplicates
        let existingURLs = Set(service.sources.map { $0.feedURL.lowercased() })

        var imported = 0
        var skipped  = 0

        for group in parsed {
            // Create folder if it has a real name (skip "Unfiled" synthetic group)
            var folderID: UUID? = nil
            if let groupName = group.name, !groupName.isEmpty, groupName.lowercased() != "unfiled" {
                // Reuse existing folder with same name, or create new
                if let existing = service.categories.first(where: { $0.name == groupName }) {
                    folderID = existing.id
                } else {
                    try service.addFolder(name: groupName, iconName: "folder.fill", colorHex: "007AFF")
                    folderID = service.categories.last?.id
                }
            }

            for feed in group.feeds {
                let normalizedURL = feed.feedURL.lowercased()
                guard !existingURLs.contains(normalizedURL) else {
                    skipped += 1
                    continue
                }
                try service.addFeed(
                    feedURL: feed.feedURL,
                    title: feed.title ?? feed.feedURL,
                    websiteURL: feed.htmlURL ?? "",
                    folderID: folderID
                )
                imported += 1
            }
        }

        return OPMLImportResult(imported: imported, skipped: skipped)
    }

    // MARK: - Private Helpers

    private func feedOutline(_ feed: FeedModel, indent: String) -> String {
        var line = "\(indent)<outline"
        line += " type=\"rss\""
        line += " text=\"\(escaped(feed.title))\""
        line += " title=\"\(escaped(feed.title))\""
        line += " xmlUrl=\"\(escaped(feed.feedURL))\""
        if !feed.websiteURL.isEmpty {
            line += " htmlUrl=\"\(escaped(feed.websiteURL))\""
        }
        line += "/>\n"
        return line
    }

    private func escaped(_ string: String) -> String {
        string
            .replacingOccurrences(of: "&",  with: "&amp;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "<",  with: "&lt;")
            .replacingOccurrences(of: ">",  with: "&gt;")
    }

    private func rfc822Date(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
        return f.string(from: date)
    }

    private func isoDateStamp(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }
}

// MARK: - Result Type

struct OPMLImportResult {
    let imported: Int
    let skipped: Int

    var summary: String {
        if skipped == 0 {
            return "Imported \(imported) feed\(imported == 1 ? "" : "s")."
        } else {
            return "Imported \(imported) feed\(imported == 1 ? "" : "s"), skipped \(skipped) duplicate\(skipped == 1 ? "" : "s")."
        }
    }
}

// MARK: - OPMLParser (SAX-based)

/// Parses OPML XML into a flat list of feed groups using XMLParser.
private final class OPMLParser: NSObject, XMLParserDelegate {

    struct FeedEntry {
        let title: String?
        let feedURL: String
        let htmlURL: String?
    }

    struct FeedGroup {
        let name: String?
        var feeds: [FeedEntry]
    }

    private let data: Data
    private var groups: [FeedGroup] = []
    private var currentGroup: FeedGroup? = nil
    private var parseError = false

    init(data: Data) {
        self.data = data
    }

    func parse() -> [FeedGroup]? {
        let parser = XMLParser(data: data)
        parser.delegate = self
        let success = parser.parse()
        guard success, !parseError else { return nil }
        // Flush the last open group
        if let g = currentGroup { groups.append(g) }
        return groups
    }

    // MARK: XMLParserDelegate

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName: String?,
        attributes: [String: String] = [:]
    ) {
        guard elementName.lowercased() == "outline" else { return }

        let xmlURL = attributes["xmlUrl"] ?? attributes["xmlurl"] ?? attributes["XMLURL"] ?? ""
        let htmlURL = attributes["htmlUrl"] ?? attributes["htmlurl"] ?? attributes["HTMLURL"]
        let text = attributes["text"] ?? attributes["title"] ?? ""

        if xmlURL.isEmpty {
            // This is a folder/group outline — flush previous group and start new
            if let g = currentGroup { groups.append(g) }
            currentGroup = FeedGroup(name: text.isEmpty ? nil : text, feeds: [])
        } else {
            // This is a feed outline
            let entry = FeedEntry(
                title: text.isEmpty ? nil : text,
                feedURL: xmlURL,
                htmlURL: htmlURL
            )
            if currentGroup != nil {
                currentGroup!.feeds.append(entry)
            } else {
                // Feed at root level with no parent group — treat as unfiled
                if groups.last?.name == nil {
                    groups[groups.count - 1].feeds.append(entry)
                } else {
                    groups.append(FeedGroup(name: nil, feeds: [entry]))
                }
            }
        }
    }

    func parser(_ parser: XMLParser, parseErrorOccurred parseError: Error) {
        self.parseError = true
    }
}
