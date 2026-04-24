//
//  RSSCatalog.swift
//  OpenRSS
//
//  Static curated feed catalog sourced from github.com/plenaryapp/awesome-rss-feeds.
//  Used by the Discover tab for Featured, Categories, and Recommended sections.
//

import SwiftUI

// MARK: - CatalogFeed

struct CatalogFeed: Identifiable, Hashable {

    /// Stable identity — the feed URL is inherently unique.
    var id: String { feedURL }

    let name: String
    let feedURL: String
    let description: String

    /// Derived website origin from the feed URL (e.g. https://example.com).
    var websiteURL: String {
        URL(string: feedURL)
            .flatMap { URL(string: "https://\($0.host ?? "")") }?
            .absoluteString ?? feedURL
    }

    // Hashable / Equatable based on URL identity
    static func == (lhs: CatalogFeed, rhs: CatalogFeed) -> Bool {
        lhs.feedURL.lowercased() == rhs.feedURL.lowercased()
    }
    func hash(into hasher: inout Hasher) { hasher.combine(feedURL.lowercased()) }
}

// MARK: - CatalogCategory

struct CatalogCategory: Identifiable {
    var id: String { name }
    let name: String
    let icon: String        // SF Symbol name
    let color: Color
    let feeds: [CatalogFeed]
}

// MARK: - RSSCatalog

enum RSSCatalog {

    // MARK: - Featured Feeds

    /// Curated "best of" feeds shown in the Featured section.
    static let featuredFeeds: [CatalogFeed] = [
        CatalogFeed(
            name: "Hacker News",
            feedURL: "https://news.ycombinator.com/rss",
            description: "Links for the intellectually curious, ranked by readers."
        ),
        CatalogFeed(
            name: "The Verge",
            feedURL: "https://www.theverge.com/rss/index.xml",
            description: "Technology, science, art, and culture — with sharp opinions."
        ),
        CatalogFeed(
            name: "NASA Breaking News",
            feedURL: "https://www.nasa.gov/rss/dyn/breaking_news.rss",
            description: "The latest announcements, discoveries, and missions from NASA."
        ),
        CatalogFeed(
            name: "Ars Technica",
            feedURL: "http://feeds.arstechnica.com/arstechnica/index",
            description: "Serving the Technologist for more than a decade. IT news, reviews, and analysis."
        ),
        CatalogFeed(
            name: "Stack Overflow Blog",
            feedURL: "https://stackoverflow.blog/feed/",
            description: "Essays, opinions, and advice on the art of computer programming."
        ),
    ]

    // MARK: - Featured Accent Gradients

    /// Gradient start/end colors cycled across featured cards in display order.
    static let featuredGradients: [[Color]] = [
        [Color(red: 1.00, green: 0.42, blue: 0.00), Color(red: 0.93, green: 0.04, blue: 0.47)],
        [Color(red: 0.28, green: 0.46, blue: 0.90), Color(red: 0.56, green: 0.33, blue: 0.91)],
        [Color(red: 0.10, green: 0.60, blue: 0.31), Color(red: 0.00, green: 0.71, blue: 0.85)],
        [Color(red: 0.97, green: 0.50, blue: 0.00), Color(red: 0.84, green: 0.16, blue: 0.16)],
        [Color(red: 0.36, green: 0.15, blue: 0.55), Color(red: 0.26, green: 0.54, blue: 0.64)],
    ]

    // MARK: - All Categories

    static let categories: [CatalogCategory] = [
        techCategory,
        appleCategory,
        programmingCategory,
        scienceCategory,
        newsCategory,
        gamingCategory,
        musicCategory,
        businessCategory,
        startupsCategory,
        spaceCategory,
        iOSDevCategory,
        booksCategory,
    ]

    // MARK: Tech

    static let techCategory = CatalogCategory(
        name: "Tech",
        icon: "cpu",
        color: .blue,
        feeds: [
            CatalogFeed(name: "Hacker News", feedURL: "https://news.ycombinator.com/rss",
                        description: "Links for the intellectually curious, ranked by readers."),
            CatalogFeed(name: "The Verge", feedURL: "https://www.theverge.com/rss/index.xml",
                        description: "All the latest in tech, science, art, and culture."),
            CatalogFeed(name: "Ars Technica", feedURL: "http://feeds.arstechnica.com/arstechnica/index",
                        description: "Serving the Technologist for more than a decade."),
            CatalogFeed(name: "TechCrunch", feedURL: "http://feeds.feedburner.com/TechCrunch",
                        description: "Startup and technology news."),
            CatalogFeed(name: "Gizmodo", feedURL: "https://gizmodo.com/rss",
                        description: "We come from the future."),
            CatalogFeed(name: "Stratechery", feedURL: "http://stratechery.com/feed/",
                        description: "On the business, strategy, and impact of technology."),
            CatalogFeed(name: "The Next Web", feedURL: "https://thenextweb.com/feed/",
                        description: "Original and proudly opinionated perspectives for Generation T."),
            CatalogFeed(name: "Engadget", feedURL: "https://www.engadget.com/rss.xml",
                        description: "Technology news, advice and features."),
            CatalogFeed(name: "Lifehacker", feedURL: "https://lifehacker.com/rss",
                        description: "Do everything better."),
            CatalogFeed(name: "Slashdot", feedURL: "http://rss.slashdot.org/Slashdot/slashdotMain",
                        description: "News for nerds, stuff that matters."),
        ]
    )

    // MARK: Apple

    static let appleCategory = CatalogCategory(
        name: "Apple",
        icon: "apple.logo",
        color: Color(.systemGray),
        feeds: [
            CatalogFeed(name: "9to5Mac", feedURL: "https://9to5mac.com/feed",
                        description: "Breaking Apple news and reviews."),
            CatalogFeed(name: "Apple Newsroom", feedURL: "https://www.apple.com/newsroom/rss-feed.rss",
                        description: "Official news and product announcements from Apple."),
            CatalogFeed(name: "AppleInsider", feedURL: "https://appleinsider.com/rss/news/",
                        description: "Apple news, rumours, and deep analysis."),
            CatalogFeed(name: "Cult of Mac", feedURL: "https://www.cultofmac.com/feed",
                        description: "Apple news, reviews, and how-tos."),
            CatalogFeed(name: "Daring Fireball", feedURL: "https://daringfireball.net/feeds/main",
                        description: "John Gruber's commentary on Apple and the tech industry."),
            CatalogFeed(name: "MacStories", feedURL: "https://www.macstories.net/feed",
                        description: "App reviews, analysis, and productivity on Apple platforms."),
            CatalogFeed(name: "MacRumors", feedURL: "http://feeds.macrumors.com/MacRumors-Mac",
                        description: "Mac news, rumors, and price guides."),
        ]
    )

    // MARK: Programming

    static let programmingCategory = CatalogCategory(
        name: "Programming",
        icon: "terminal.fill",
        color: .orange,
        feeds: [
            CatalogFeed(name: "Stack Overflow Blog", feedURL: "https://stackoverflow.blog/feed/",
                        description: "Essays, opinions, and advice on the act of computer programming."),
            CatalogFeed(name: "GitHub Blog", feedURL: "https://github.blog/feed/",
                        description: "Updates, ideas, and inspiration from GitHub."),
            CatalogFeed(name: "Joel on Software", feedURL: "https://www.joelonsoftware.com/feed/",
                        description: "Software development and engineering management."),
            CatalogFeed(name: "Martin Fowler", feedURL: "https://martinfowler.com/feed.atom",
                        description: "Architecture, design patterns, and agile practices."),
            CatalogFeed(name: "Netflix TechBlog", feedURL: "https://netflixtechblog.com/feed",
                        description: "Netflix's world-class engineering and data science."),
            CatalogFeed(name: "Coding Horror", feedURL: "https://feeds.feedburner.com/codinghorror",
                        description: "Programming and human factors by Jeff Atwood."),
            CatalogFeed(name: "InfoQ", feedURL: "https://feed.infoq.com",
                        description: "Software development news, trends, and deep dives."),
            CatalogFeed(name: "Spotify Engineering", feedURL: "https://labs.spotify.com/feed/",
                        description: "Spotify's official technology and engineering blog."),
            CatalogFeed(name: "Overreacted", feedURL: "https://overreacted.io/rss.xml",
                        description: "Personal blog by Dan Abramov — React and JavaScript insights."),
            CatalogFeed(name: "Facebook Engineering", feedURL: "https://engineering.fb.com/feed/",
                        description: "Meta's engineering and infrastructure blog."),
        ]
    )

    // MARK: Science

    static let scienceCategory = CatalogCategory(
        name: "Science",
        icon: "waveform",
        color: .purple,
        feeds: [
            CatalogFeed(name: "BBC Science & Environment",
                        feedURL: "http://feeds.bbci.co.uk/news/science_and_environment/rss.xml",
                        description: "Science and environment news from the BBC."),
            CatalogFeed(name: "Scientific American",
                        feedURL: "http://rss.sciam.com/sciam/60secsciencepodcast",
                        description: "60-Second Science podcast from Scientific American."),
            CatalogFeed(name: "Gizmodo Science", feedURL: "https://gizmodo.com/tag/science/rss",
                        description: "Science news and discoveries from Gizmodo."),
            CatalogFeed(name: "Hidden Brain", feedURL: "https://feeds.npr.org/510308/podcast.xml",
                        description: "Exploring unconscious patterns that drive human behavior."),
            CatalogFeed(name: "FlowingData", feedURL: "https://flowingdata.com/feed",
                        description: "Data visualization, statistics, and infographics."),
            CatalogFeed(name: "Invisibilia", feedURL: "https://feeds.npr.org/510307/podcast.xml",
                        description: "The invisible forces that shape human behavior."),
        ]
    )

    // MARK: News

    static let newsCategory = CatalogCategory(
        name: "News",
        icon: "newspaper.fill",
        color: .red,
        feeds: [
            CatalogFeed(name: "BBC News – World",
                        feedURL: "http://feeds.bbci.co.uk/news/world/rss.xml",
                        description: "World news from the BBC."),
            CatalogFeed(name: "NYT World News",
                        feedURL: "https://rss.nytimes.com/services/xml/rss/nyt/World.xml",
                        description: "World news from The New York Times."),
            CatalogFeed(name: "Google News",
                        feedURL: "https://news.google.com/rss",
                        description: "Top stories aggregated by Google News."),
            CatalogFeed(name: "Washington Post",
                        feedURL: "http://feeds.washingtonpost.com/rss/world",
                        description: "World news from The Washington Post."),
            CatalogFeed(name: "CNBC International",
                        feedURL: "https://www.cnbc.com/id/100727362/device/rss/rss.html",
                        description: "International top news and analysis from CNBC."),
            CatalogFeed(name: "r/worldnews",
                        feedURL: "https://www.reddit.com/r/worldnews/.rss",
                        description: "Major news stories from around the world."),
            CatalogFeed(name: "NDTV World News",
                        feedURL: "http://feeds.feedburner.com/ndtvnews-world-news",
                        description: "World news from NDTV."),
        ]
    )

    // MARK: Gaming

    static let gamingCategory = CatalogCategory(
        name: "Gaming",
        icon: "gamecontroller.fill",
        color: .green,
        feeds: [
            CatalogFeed(name: "Kotaku", feedURL: "https://kotaku.com/rss",
                        description: "Video game culture, reviews, and news."),
            CatalogFeed(name: "IGN", feedURL: "http://feeds.ign.com/ign/all",
                        description: "Video games, movies, TV and more."),
            CatalogFeed(name: "Eurogamer", feedURL: "https://www.eurogamer.net/?format=rss",
                        description: "Video game reviews, previews, and news."),
            CatalogFeed(name: "GameSpot", feedURL: "https://www.gamespot.com/feeds/mashup/",
                        description: "Video game reviews and industry news."),
            CatalogFeed(name: "Indie Games Plus", feedURL: "https://indiegamesplus.com/feed",
                        description: "Indie game news, reviews, and features."),
            CatalogFeed(name: "Gamasutra", feedURL: "http://feeds.feedburner.com/GamasutraNews",
                        description: "The art & business of making games."),
            CatalogFeed(name: "Escapist Magazine", feedURL: "https://www.escapistmagazine.com/v2/feed/",
                        description: "Video game and pop-culture commentary."),
        ]
    )

    // MARK: Music

    static let musicCategory = CatalogCategory(
        name: "Music",
        icon: "music.note",
        color: .pink,
        feeds: [
            CatalogFeed(name: "Pitchfork", feedURL: "http://pitchfork.com/rss/news",
                        description: "Music reviews, news, and features."),
            CatalogFeed(name: "Billboard", feedURL: "https://www.billboard.com/articles/rss.xml",
                        description: "Charts, artist features, and industry news."),
            CatalogFeed(name: "Consequence of Sound", feedURL: "http://consequenceofsound.net/feed",
                        description: "Music, film, and television news and reviews."),
            CatalogFeed(name: "Song Exploder", feedURL: "http://songexploder.net/feed",
                        description: "Musicians take apart their songs piece by piece."),
            CatalogFeed(name: "Music Business Worldwide", feedURL: "https://www.musicbusinessworldwide.com/feed/",
                        description: "Global music industry news and analysis."),
            CatalogFeed(name: "Your EDM", feedURL: "https://www.youredm.com/feed",
                        description: "Electronic dance music news, reviews, and culture."),
        ]
    )

    // MARK: Business

    static let businessCategory = CatalogCategory(
        name: "Business",
        icon: "briefcase.fill",
        color: .teal,
        feeds: [
            CatalogFeed(name: "Forbes Business", feedURL: "https://www.forbes.com/business/feed/",
                        description: "Business news and analysis from Forbes."),
            CatalogFeed(name: "Fortune", feedURL: "https://fortune.com/feed",
                        description: "Business leadership and corporate strategy."),
            CatalogFeed(name: "Inc.com", feedURL: "https://www.inc.com/rss/",
                        description: "Small business and entrepreneurship advice."),
            CatalogFeed(name: "Economic Times", feedURL: "https://economictimes.indiatimes.com/rssfeedsdefault.cms",
                        description: "India and global business and economic news."),
            CatalogFeed(name: "Seeking Alpha", feedURL: "https://seekingalpha.com/market_currents.xml",
                        description: "Breaking news from financial markets."),
            CatalogFeed(name: "Duct Tape Marketing", feedURL: "https://ducttape.libsyn.com/rss",
                        description: "Small business marketing strategy and advice."),
        ]
    )

    // MARK: Startups

    static let startupsCategory = CatalogCategory(
        name: "Startups",
        icon: "flame.fill",
        color: Color(red: 1.0, green: 0.4, blue: 0.1),
        feeds: [
            CatalogFeed(name: "Hacker News: Front Page", feedURL: "https://hnrss.org/frontpage",
                        description: "Top stories from Hacker News."),
            CatalogFeed(name: "AVC", feedURL: "https://avc.com/feed/",
                        description: "Venture capital musings by Fred Wilson of USV."),
            CatalogFeed(name: "Both Sides of the Table",
                        feedURL: "https://bothsidesofthetable.com/feed",
                        description: "Startup advice from a VC-turned-entrepreneur."),
            CatalogFeed(name: "Entrepreneur", feedURL: "http://feeds.feedburner.com/entrepreneur/latest",
                        description: "Startup and entrepreneurship news and advice."),
            CatalogFeed(name: "Forbes Entrepreneurs",
                        feedURL: "https://www.forbes.com/entrepreneurs/feed/",
                        description: "Entrepreneurship insight and profiles from Forbes."),
            CatalogFeed(name: "Feld Thoughts", feedURL: "https://feld.com/feed",
                        description: "Brad Feld on venture capital, startups, and life."),
        ]
    )

    // MARK: Space

    static let spaceCategory = CatalogCategory(
        name: "Space",
        icon: "moon.stars.fill",
        color: .indigo,
        feeds: [
            CatalogFeed(name: "NASA Breaking News",
                        feedURL: "https://www.nasa.gov/rss/dyn/breaking_news.rss",
                        description: "The latest news and announcements from NASA."),
            CatalogFeed(name: "Space.com", feedURL: "https://www.space.com/feeds/all",
                        description: "The latest in space science and exploration."),
            CatalogFeed(name: "The Guardian: Space",
                        feedURL: "https://www.theguardian.com/science/space/rss",
                        description: "Space news from The Guardian."),
            CatalogFeed(name: "Sky & Telescope", feedURL: "https://www.skyandtelescope.com/feed/",
                        description: "Astronomy news, observing guides, and gear."),
            CatalogFeed(name: "r/space",
                        feedURL: "https://www.reddit.com/r/space/.rss?format=xml",
                        description: "News, articles and discussion about space."),
            CatalogFeed(name: "New Scientist: Space",
                        feedURL: "https://www.newscientist.com/subject/space/feed/",
                        description: "Space and astronomy from New Scientist."),
        ]
    )

    // MARK: iOS Development

    static let iOSDevCategory = CatalogCategory(
        name: "iOS Dev",
        icon: "swift",
        color: Color(red: 0.95, green: 0.45, blue: 0.15),
        feeds: [
            CatalogFeed(name: "Swift by Sundell",
                        feedURL: "https://www.swiftbysundell.com/feed.rss",
                        description: "Articles, podcasts and tips about Swift development."),
            CatalogFeed(name: "Apple Developer News",
                        feedURL: "https://developer.apple.com/news/rss/news.rss",
                        description: "Latest news and announcements from Apple Developer."),
            CatalogFeed(name: "Augmented Code",
                        feedURL: "https://augmentedcode.io/feed/",
                        description: "iOS and Swift development tips and tutorials."),
            CatalogFeed(name: "Ole Begemann",
                        feedURL: "https://oleb.net/blog/atom.xml",
                        description: "Deep-dive iOS and Swift development articles."),
            CatalogFeed(name: "More Than Just Code",
                        feedURL: "https://feeds.fireside.fm/mtjc/rss",
                        description: "iOS and Swift development news and advice."),
        ]
    )

    // MARK: Books

    static let booksCategory = CatalogCategory(
        name: "Books",
        icon: "books.vertical.fill",
        color: Color(red: 0.55, green: 0.35, blue: 0.15),
        feeds: [
            CatalogFeed(name: "Book Riot", feedURL: "https://bookriot.com/feed/",
                        description: "Book reviews, lists, and literary culture."),
            CatalogFeed(name: "Kirkus Reviews", feedURL: "https://www.kirkusreviews.com/feeds/rss/",
                        description: "Authoritative book reviews since 1933."),
            CatalogFeed(name: "r/books", feedURL: "https://reddit.com/r/books/.rss",
                        description: "A place for readers to share and discuss."),
            CatalogFeed(name: "A Year of Reading the World",
                        feedURL: "https://ayearofreadingtheworld.com/feed/",
                        description: "Reading and reviewing books from every country."),
        ]
    )

    // MARK: - Recommended Feeds Logic

    /// Returns up to `limit` catalog feeds the user hasn't subscribed to yet,
    /// weighted toward categories where the user already has subscriptions
    /// (a proxy for source affinity without requiring the full SQLite query).
    ///
    /// - Parameters:
    ///   - subscribedURLs: Lowercased set of all user-subscribed feed URLs.
    ///   - limit: Maximum number of feeds to return (default: 8).
    static func recommendedFeeds(
        subscribedURLs: Set<String>,
        limit: Int = 8
    ) -> [CatalogFeed] {
        // Score each category: more user subscriptions → higher score
        let scored = categories.map { cat -> (CatalogCategory, Int) in
            let count = cat.feeds.filter { subscribedURLs.contains($0.feedURL.lowercased()) }.count
            return (cat, count)
        }
        // Categories with subscriptions first, rest in original order
        let sorted = scored.sorted { $0.1 > $1.1 }

        var result: [CatalogFeed] = []
        var seen = Set<String>()

        for (cat, _) in sorted {
            for feed in cat.feeds {
                let url = feed.feedURL.lowercased()
                guard !subscribedURLs.contains(url), !seen.contains(url) else { continue }
                result.append(feed)
                seen.insert(url)
                if result.count >= limit { return result }
            }
        }
        return result
    }

    /// Finds which catalog category a given feed belongs to (if any).
    static func category(for feed: CatalogFeed) -> CatalogCategory? {
        categories.first { $0.feeds.contains(feed) }
    }
}
