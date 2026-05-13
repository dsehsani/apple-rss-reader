//
//  FeedCatalogService.swift
//  OpenRSS
//
//  Dynamically fetches the awesome-rss-feeds GitHub catalog at runtime,
//  parses each category's OPML file, and caches results to disk for 24 hours.
//  Falls back to the static RSSCatalog on network failure.
//

import SwiftUI
import Observation

// MARK: - FeedCatalogService

@Observable
final class FeedCatalogService {

    static let shared = FeedCatalogService()

    // MARK: - Published State

    private(set) var categories: [CatalogCategory] = []
    private(set) var isLoading = false
    private(set) var loadError: String? = nil

    // MARK: - Cache Config

    private let cacheURL: URL
    private let cacheTTL: TimeInterval = 86_400   // 24 hours

    private init() {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        cacheURL = dir.appendingPathComponent("feed_catalog_cache.json")
    }

    // MARK: - Public API

    /// All feeds across all categories, deduplicated by URL.
    var allFeeds: [CatalogFeed] {
        var seen = Set<String>()
        return categories.flatMap(\.feeds).filter {
            seen.insert($0.feedURL.lowercased()).inserted
        }
    }

    /// Load from cache if fresh; otherwise fetch from GitHub.
    func loadIfNeeded() async {
        if let cached = readCache(), !isCacheStale() {
            if categories.isEmpty {
                await MainActor.run { categories = cached }
            }
            return
        }
        await refresh()
    }

    /// Force a fresh fetch from GitHub.
    func refresh() async {
        await MainActor.run {
            isLoading = true
            loadError = nil
        }
        do {
            let fetched = try await fetchAllCategories()
            writeCache(fetched)
            await MainActor.run {
                categories = fetched
                isLoading = false
            }
        } catch {
            await MainActor.run {
                loadError = error.localizedDescription
                // Fall back to static catalog so the UI is never empty
                if categories.isEmpty {
                    categories = RSSCatalog.categories
                }
                isLoading = false
            }
        }
    }

    // MARK: - GitHub Fetch

    private struct GitHubFile: Decodable {
        let name: String
        let download_url: String?
    }

    private func fetchAllCategories() async throws -> [CatalogCategory] {
        let apiURL = URL(string:
            "https://api.github.com/repos/plenaryapp/awesome-rss-feeds/contents/recommended/with_category"
        )!
        var req = URLRequest(url: apiURL)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.timeoutInterval = 15

        let (data, _) = try await URLSession.shared.data(for: req)
        let files = try JSONDecoder().decode([GitHubFile].self, from: data)
        let opmlFiles = files.filter { $0.name.hasSuffix(".opml") && $0.download_url != nil }

        return try await withThrowingTaskGroup(of: CatalogCategory?.self) { group in
            for file in opmlFiles {
                let categoryName = String(file.name.dropLast(5)) // strip ".opml"
                let rawURL = file.download_url!
                group.addTask {
                    try await self.fetchCategory(name: categoryName, rawURL: rawURL)
                }
            }
            var results: [CatalogCategory] = []
            for try await cat in group {
                if let cat { results.append(cat) }
            }
            // Sort: known categories first (matching static order), then alphabetical
            return results.sorted { Self.sortOrder($0.name) < Self.sortOrder($1.name) }
        }
    }

    private func fetchCategory(name: String, rawURL: String) async throws -> CatalogCategory? {
        guard let url = URL(string: rawURL) else { return nil }
        var req = URLRequest(url: url)
        req.timeoutInterval = 10
        let (data, _) = try await URLSession.shared.data(for: req)
        let feeds = CatalogOPMLParser.parse(data: data)
        guard !feeds.isEmpty else { return nil }
        let (icon, color) = Self.iconAndColor(for: name)
        return CatalogCategory(name: name, icon: icon, color: color, feeds: feeds)
    }

    // MARK: - Sort Order

    /// Puts the most popular categories first, then falls back to alphabetical.
    private static let preferredOrder = [
        "Tech", "News", "Programming", "Science", "Apple", "Gaming",
        "Music", "Business & Economy", "Startups", "Space", "iOS Development",
        "Books", "Web Development", "Movies", "Sports", "Food", "Travel",
        "Personal Finance", "Photography", "Television", "History",
        "Android Development", "Android", "Architecture", "Beauty", "Cars",
        "Cricket", "DIY", "Fashion", "Football", "Funny",
        "Interior Design", "Tennis", "UI - UX",
    ]

    private static func sortOrder(_ name: String) -> Int {
        preferredOrder.firstIndex(of: name) ?? preferredOrder.count
    }

    // MARK: - Icon / Color Mapping

    static func iconAndColor(for name: String) -> (String, Color) {
        switch name.lowercased() {
        case "tech":                        return ("cpu", .blue)
        case "apple":                       return ("apple.logo", Color(.systemGray))
        case "programming":                 return ("terminal.fill", .orange)
        case "science":                     return ("waveform", .purple)
        case "news":                        return ("newspaper.fill", .red)
        case "gaming":                      return ("gamecontroller.fill", .green)
        case "music":                       return ("music.note", .pink)
        case "business & economy",
             "business", "economy":        return ("briefcase.fill", .teal)
        case "startups":                    return ("flame.fill", Color(red: 1.0, green: 0.4, blue: 0.1))
        case "space":                       return ("moon.stars.fill", .indigo)
        case "ios development":             return ("swift", Color(red: 0.95, green: 0.45, blue: 0.15))
        case "books":                       return ("books.vertical.fill", Color(red: 0.55, green: 0.35, blue: 0.15))
        case "android development",
             "android":                    return ("iphone", Color(red: 0.2, green: 0.7, blue: 0.3))
        case "architecture":               return ("building.columns.fill", .brown)
        case "beauty":                     return ("sparkles", .pink)
        case "cars":                       return ("car.fill", Color(red: 0.6, green: 0.2, blue: 0.1))
        case "cricket":                    return ("figure.cricket", .green)
        case "diy":                        return ("hammer.fill", .orange)
        case "fashion":                    return ("tshirt.fill", Color(red: 0.7, green: 0.3, blue: 0.7))
        case "food":                       return ("fork.knife", Color(red: 0.9, green: 0.4, blue: 0.1))
        case "football":                   return ("figure.american.football", .green)
        case "funny":                      return ("face.smiling.fill", .yellow)
        case "history":                    return ("clock.fill", .brown)
        case "interior design":            return ("house.fill", .teal)
        case "movies":                     return ("film.fill", Color(red: 0.5, green: 0.1, blue: 0.7))
        case "personal finance":           return ("dollarsign.circle.fill", Color(red: 0.1, green: 0.6, blue: 0.3))
        case "photography":                return ("camera.fill", Color(.systemGray))
        case "sports":                     return ("sportscourt.fill", .orange)
        case "television":                 return ("tv.fill", .blue)
        case "tennis":                     return ("figure.tennis", Color(red: 0.1, green: 0.6, blue: 0.2))
        case "travel":                     return ("airplane", .cyan)
        case "ui - ux":                    return ("paintbrush.fill", Color(red: 0.4, green: 0.2, blue: 0.8))
        case "web development":            return ("globe", Color(red: 0.2, green: 0.5, blue: 0.9))
        default:                           return ("dot.radiowaves.left.and.right", .gray)
        }
    }

    // MARK: - Disk Cache

    private struct CacheFile: Codable {
        struct Feed: Codable {
            let name: String
            let feedURL: String
            let description: String
        }
        struct Category: Codable {
            let name: String
            let feeds: [Feed]
        }
        let fetchedAt: Date
        let categories: [Category]
    }

    private func isCacheStale() -> Bool {
        guard
            let attrs = try? FileManager.default.attributesOfItem(atPath: cacheURL.path),
            let modified = attrs[.modificationDate] as? Date
        else { return true }
        return Date().timeIntervalSince(modified) > cacheTTL
    }

    private func readCache() -> [CatalogCategory]? {
        guard
            let data = try? Data(contentsOf: cacheURL),
            let cache = try? JSONDecoder().decode(CacheFile.self, from: data)
        else { return nil }

        return cache.categories.map { cat in
            let feeds = cat.feeds.map {
                CatalogFeed(name: $0.name, feedURL: $0.feedURL, description: $0.description)
            }
            let (icon, color) = Self.iconAndColor(for: cat.name)
            return CatalogCategory(name: cat.name, icon: icon, color: color, feeds: feeds)
        }
    }

    private func writeCache(_ categories: [CatalogCategory]) {
        let file = CacheFile(
            fetchedAt: Date(),
            categories: categories.map { cat in
                .init(
                    name: cat.name,
                    feeds: cat.feeds.map {
                        .init(name: $0.name, feedURL: $0.feedURL, description: $0.description)
                    }
                )
            }
        )
        if let data = try? JSONEncoder().encode(file) {
            try? data.write(to: cacheURL, options: .atomic)
        }
    }
}

// MARK: - CatalogOPMLParser

/// Lightweight SAX parser that extracts feed outlines from an OPML document.
private final class CatalogOPMLParser: NSObject, XMLParserDelegate {

    private var feeds: [CatalogFeed] = []

    static func parse(data: Data) -> [CatalogFeed] {
        let instance = CatalogOPMLParser()
        let parser = XMLParser(data: data)
        parser.delegate = instance
        parser.parse()
        return instance.feeds
    }

    func parser(
        _ parser: XMLParser,
        didStartElement element: String,
        namespaceURI: String?,
        qualifiedName: String?,
        attributes: [String: String] = [:]
    ) {
        guard element.lowercased() == "outline" else { return }
        // Only process feed outlines (those with an xmlUrl attribute)
        guard
            let xmlURL = attributes["xmlUrl"] ?? attributes["xmlurl"] ?? attributes["XMLURL"],
            !xmlURL.isEmpty
        else { return }

        let name = (attributes["text"] ?? attributes["title"] ?? "").trimmingCharacters(in: .whitespaces)
        let desc = (attributes["description"] ?? "").trimmingCharacters(in: .whitespaces)
        feeds.append(CatalogFeed(
            name: name.isEmpty ? xmlURL : name,
            feedURL: xmlURL,
            description: desc
        ))
    }
}
