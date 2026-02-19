//
//  MockDataService.swift
//  OpenRSS
//
//  Created by Darius Ehsani on 2/3/26.
//

import Foundation
import SwiftUI

/// Protocol for feed data service (enables dependency injection)
protocol FeedDataService {
    var categories: [Category] { get }
    var sources: [Source] { get }
    var articles: [Article] { get }

    func source(for id: UUID) -> Source?
    func category(for id: UUID) -> Category?
    func articlesForCategory(_ categoryID: UUID) -> [Article]
    func articlesForSource(_ sourceID: UUID) -> [Article]
    func unreadCountForCategory(_ categoryID: UUID) -> Int
    func unreadCountForSource(_ sourceID: UUID) -> Int
}

/// Mock data service providing sample RSS data for UI development
final class MockDataService: FeedDataService {

    // MARK: - Singleton

    static let shared = MockDataService()

    // MARK: - Data Storage

    private(set) var categories: [Category] = []
    private(set) var sources: [Source] = []
    private(set) var articles: [Article] = []

    // MARK: - Initialization

    private init() {
        // Data is now managed by SwiftDataService + SwiftData persistence.
        // MockDataService starts empty; it is kept only as a test/preview stub.
    }

    // MARK: - Categories Setup

    private func setupCategories() {
        categories = [
            Category(
                id: CategoryIDs.techNews,
                name: "Tech News",
                icon: "cpu.fill",
                color: .blue,
                sortOrder: 0
            ),
            Category(
                id: CategoryIDs.design,
                name: "Design",
                icon: "paintbrush.fill",
                color: .orange,
                sortOrder: 1
            ),
            Category(
                id: CategoryIDs.work,
                name: "Work",
                icon: "briefcase.fill",
                color: .green,
                sortOrder: 2
            ),
            Category(
                id: CategoryIDs.productivity,
                name: "Productivity",
                icon: "checkmark.circle.fill",
                color: .purple,
                sortOrder: 3
            ),
            Category(
                id: CategoryIDs.personal,
                name: "Personal",
                icon: "person.fill",
                color: .pink,
                sortOrder: 4
            )
        ]
    }

    // MARK: - Sources Setup

    private func setupSources() {
        sources = [
            // Tech News Sources
            Source(
                id: SourceIDs.techCrunch,
                name: "TechCrunch",
                feedURL: "https://techcrunch.com/feed/",
                websiteURL: "https://techcrunch.com",
                icon: "bolt.fill",
                iconColor: .blue,
                categoryID: CategoryIDs.techNews
            ),
            Source(
                id: SourceIDs.theVerge,
                name: "The Verge",
                feedURL: "https://theverge.com/rss/index.xml",
                websiteURL: "https://theverge.com",
                icon: "v.circle.fill",
                iconColor: .purple,
                categoryID: CategoryIDs.techNews
            ),
            Source(
                id: SourceIDs.arstechnica,
                name: "Ars Technica",
                feedURL: "https://arstechnica.com/feed/",
                websiteURL: "https://arstechnica.com",
                icon: "atom",
                iconColor: .orange,
                categoryID: CategoryIDs.techNews
            ),
            Source(
                id: SourceIDs.wired,
                name: "Wired",
                feedURL: "https://wired.com/feed/",
                websiteURL: "https://wired.com",
                icon: "w.circle.fill",
                iconColor: .black,
                categoryID: CategoryIDs.techNews
            ),

            // Design Sources
            Source(
                id: SourceIDs.smashingMagazine,
                name: "Smashing Magazine",
                feedURL: "https://smashingmagazine.com/feed/",
                websiteURL: "https://smashingmagazine.com",
                icon: "paintbrush.fill",
                iconColor: .orange,
                categoryID: CategoryIDs.design
            ),
//            Source(
//                id: SourceIDs.designernews,
//                name: "Designer News",
//                feedURL: "https://www.designernews.co/?format=rss",
//                websiteURL: "https://designernews.co",
//                icon: "newspaper.fill",
//                iconColor: .blue,
//                categoryID: CategoryIDs.design
//            ),
            Source(
                id: SourceIDs.designernews,
                name: "A List Apart",
                feedURL: "https://alistapart.com/main/feed/",
                websiteURL: "https://alistapart.com",
                icon: "newspaper.fill",
                iconColor: .blue,
                categoryID: CategoryIDs.design
            ),
            
            Source(
                id: SourceIDs.abduzeedo,
                name: "Abduzeedo",
                feedURL: "https://abduzeedo.com/feed/",
                websiteURL: "https://abduzeedo.com",
                icon: "a.circle.fill",
                iconColor: .pink,
                categoryID: CategoryIDs.design
            ),

            // Work Sources
//            Source(
//                id: SourceIDs.hbr,
//                name: "Harvard Business Review",
//                feedURL: "https://feeds.harvardbusiness.org/harvardbusiness?format=xml",
//                websiteURL: "https://hbr.org",
//                icon: "building.columns.fill",
//                iconColor: .red,
//                categoryID: CategoryIDs.work
//            ),
            Source(
                id: SourceIDs.hbr, // reuse the same id for now OR create a new one later
                name: "MIT Sloan Management Review",
                feedURL: "https://sloanreview.mit.edu/feed/",
                websiteURL: "https://sloanreview.mit.edu",
                icon: "building.columns.fill",
                iconColor: .red,
                categoryID: CategoryIDs.work
            ),
            
            Source(
                id: SourceIDs.fastCompany,
                name: "Fast Company",
                feedURL: "https://www.fastcompany.com/work-life/rss",
                websiteURL: "https://fastcompany.com",
                icon: "hare.fill",
                iconColor: .green,
                categoryID: CategoryIDs.work
            ),

            // Productivity Sources
            Source(
                id: SourceIDs.lifehacker,
                name: "Lifehacker",
                feedURL: "https://lifehacker.com/feed/",
                websiteURL: "https://lifehacker.com",
                icon: "lightbulb.fill",
                iconColor: .yellow,
                categoryID: CategoryIDs.productivity
            ),
         /* 404
            Source(
                id: SourceIDs.zenHabits,
                name: "Zen Habits",
                feedURL: "https://zenhabits.net/feed/",
                websiteURL: "https://zenhabits.net",
                icon: "leaf.fill",
                iconColor: .green,
                categoryID: CategoryIDs.productivity
            ),
          */
            // Personal Sources
            Source(
                id: SourceIDs.brainPickings,
                name: "The Marginalian",
                feedURL: "https://themarginalian.org/feed/",
                websiteURL: "https://themarginalian.org",
                icon: "book.fill",
                iconColor: .indigo,
                categoryID: CategoryIDs.personal
            ),
            Source(
                id: SourceIDs.waitButWhy,
                name: "Wait But Why",
                feedURL: "https://waitbutwhy.com/feed/",
                websiteURL: "https://waitbutwhy.com",
                icon: "questionmark.circle.fill",
                iconColor: .cyan,
                categoryID: CategoryIDs.personal
            )
        ]
    }

    // MARK: - Articles Setup

    private func setupArticles() {
        articles = [
            // Tech News Articles
            Article(
                title: "The Future of AI is Local",
                excerpt: "Privacy-focused on-device processing is becoming the new standard for modern mobile applications. Large language models are shrinking to fit your pocket.",
                sourceID: SourceIDs.techCrunch,
                categoryID: CategoryIDs.techNews,
                publishedAt: Date().addingTimeInterval(-2 * 3600),
                isRead: false,
                readTimeMinutes: 6
            ),
            Article(
                title: "Apple Announces New M4 Chip Architecture",
                excerpt: "The next generation of Apple Silicon promises 50% faster neural engine performance and improved power efficiency across all device categories.",
                sourceID: SourceIDs.theVerge,
                categoryID: CategoryIDs.techNews,
                publishedAt: Date().addingTimeInterval(-4 * 3600),
                isRead: false,
                readTimeMinutes: 8
            ),
            Article(
                title: "The State of Web Assembly in 2026",
                excerpt: "How WASM is revolutionizing browser-based applications and enabling near-native performance for complex web apps.",
                sourceID: SourceIDs.arstechnica,
                categoryID: CategoryIDs.techNews,
                publishedAt: Date().addingTimeInterval(-6 * 3600),
                isRead: true,
                readTimeMinutes: 12
            ),
            Article(
                title: "Quantum Computing Reaches New Milestone",
                excerpt: "Researchers demonstrate stable qubits at room temperature, bringing practical quantum computers closer to reality.",
                sourceID: SourceIDs.wired,
                categoryID: CategoryIDs.techNews,
                publishedAt: Date().addingTimeInterval(-8 * 3600),
                isRead: false,
                readTimeMinutes: 10
            ),
            Article(
                title: "The Rise of Edge Computing",
                excerpt: "Why processing data closer to its source is becoming essential for IoT and real-time applications.",
                sourceID: SourceIDs.techCrunch,
                categoryID: CategoryIDs.techNews,
                publishedAt: Date().addingTimeInterval(-12 * 3600),
                isRead: true,
                readTimeMinutes: 7
            ),
            Article(
                title: "Swift 6.0: What Developers Need to Know",
                excerpt: "A comprehensive look at the new concurrency features, memory safety improvements, and breaking changes in Swift 6.",
                sourceID: SourceIDs.arstechnica,
                categoryID: CategoryIDs.techNews,
                publishedAt: Date().addingTimeInterval(-1 * 86400),
                isRead: false,
                readTimeMinutes: 15
            ),

            // Design Articles
            Article(
                title: "Mastering Liquid Glass Effects",
                excerpt: "How to achieve perfect translucency and background blurs in your next mobile project using system APIs and modern CSS techniques.",
                sourceID: SourceIDs.smashingMagazine,
                categoryID: CategoryIDs.design,
                publishedAt: Date().addingTimeInterval(-5 * 3600),
                isRead: false,
                readTimeMinutes: 8
            ),
            Article(
                title: "The Evolution of iOS Design Language",
                excerpt: "From skeuomorphism to flat design to vibrancy: tracing Apple's design philosophy over the years.",
                sourceID: SourceIDs.designernews,
                categoryID: CategoryIDs.design,
                publishedAt: Date().addingTimeInterval(-10 * 3600),
                isRead: false,
                readTimeMinutes: 11
            ),
            Article(
                title: "Color Theory for Digital Interfaces",
                excerpt: "Understanding how color psychology impacts user behavior and how to create accessible color palettes.",
                sourceID: SourceIDs.abduzeedo,
                categoryID: CategoryIDs.design,
                publishedAt: Date().addingTimeInterval(-18 * 3600),
                isRead: true,
                readTimeMinutes: 9
            ),
            Article(
                title: "Designing for Variable Fonts",
                excerpt: "A practical guide to implementing responsive typography with variable font axes.",
                sourceID: SourceIDs.smashingMagazine,
                categoryID: CategoryIDs.design,
                publishedAt: Date().addingTimeInterval(-2 * 86400),
                isRead: false,
                readTimeMinutes: 14
            ),
            Article(
                title: "Motion Design Principles for Mobile",
                excerpt: "Creating meaningful animations that enhance user experience without sacrificing performance.",
                sourceID: SourceIDs.designernews,
                categoryID: CategoryIDs.design,
                publishedAt: Date().addingTimeInterval(-3 * 86400),
                isRead: true,
                readTimeMinutes: 10
            ),

            // Work Articles
            Article(
                title: "The Rise of Minimalist Workspaces",
                excerpt: "Exploring how physical environment impacts digital productivity and the tools that bridge the gap between office and home.",
                sourceID: SourceIDs.hbr,
                categoryID: CategoryIDs.work,
                publishedAt: Date().addingTimeInterval(-8 * 3600),
                isRead: false,
                readTimeMinutes: 7
            ),
            Article(
                title: "Remote Work: Three Years Later",
                excerpt: "What we've learned about distributed teams, async communication, and maintaining company culture.",
                sourceID: SourceIDs.fastCompany,
                categoryID: CategoryIDs.work,
                publishedAt: Date().addingTimeInterval(-14 * 3600),
                isRead: false,
                readTimeMinutes: 9
            ),
            Article(
                title: "The Art of Technical Leadership",
                excerpt: "Balancing hands-on coding with mentorship, strategy, and stakeholder communication.",
                sourceID: SourceIDs.hbr,
                categoryID: CategoryIDs.work,
                publishedAt: Date().addingTimeInterval(-1 * 86400),
                isRead: true,
                readTimeMinutes: 12
            ),
            Article(
                title: "Building Inclusive Engineering Teams",
                excerpt: "Practical strategies for creating diverse, equitable, and high-performing technical organizations.",
                sourceID: SourceIDs.fastCompany,
                categoryID: CategoryIDs.work,
                publishedAt: Date().addingTimeInterval(-2 * 86400),
                isRead: false,
                readTimeMinutes: 8
            ),

            // Productivity Articles
            Article(
                title: "Digital Minimalism in Practice",
                excerpt: "Reducing screen time and notification overload while staying connected to what matters.",
                sourceID: SourceIDs.lifehacker,
                categoryID: CategoryIDs.productivity,
                publishedAt: Date().addingTimeInterval(-3 * 3600),
                isRead: false,
                readTimeMinutes: 6
            ),
            Article(
                title: "The Pomodoro Technique Reimagined",
                excerpt: "Modern variations on the classic time management method for knowledge workers.",
                sourceID: SourceIDs.zenHabits,
                categoryID: CategoryIDs.productivity,
                publishedAt: Date().addingTimeInterval(-9 * 3600),
                isRead: true,
                readTimeMinutes: 5
            ),
            Article(
                title: "Building a Second Brain",
                excerpt: "How to organize your digital notes and references for maximum retrieval and creativity.",
                sourceID: SourceIDs.lifehacker,
                categoryID: CategoryIDs.productivity,
                publishedAt: Date().addingTimeInterval(-20 * 3600),
                isRead: false,
                readTimeMinutes: 11
            ),
            Article(
                title: "The Power of Weekly Reviews",
                excerpt: "A simple habit that transforms how you plan, reflect, and course-correct.",
                sourceID: SourceIDs.zenHabits,
                categoryID: CategoryIDs.productivity,
                publishedAt: Date().addingTimeInterval(-2 * 86400),
                isRead: false,
                readTimeMinutes: 7
            ),

            // Personal Articles
            Article(
                title: "The Science of Habit Formation",
                excerpt: "What neuroscience reveals about building lasting habits and breaking destructive ones.",
                sourceID: SourceIDs.brainPickings,
                categoryID: CategoryIDs.personal,
                publishedAt: Date().addingTimeInterval(-7 * 3600),
                isRead: false,
                readTimeMinutes: 13
            ),
            Article(
                title: "Why We Procrastinate",
                excerpt: "It's not about laziness—understanding the emotional roots of putting things off.",
                sourceID: SourceIDs.waitButWhy,
                categoryID: CategoryIDs.personal,
                publishedAt: Date().addingTimeInterval(-16 * 3600),
                isRead: true,
                readTimeMinutes: 18
            ),
            Article(
                title: "The Art of Reading Deeply",
                excerpt: "Strategies for slower, more intentional reading in an age of skimming and scrolling.",
                sourceID: SourceIDs.brainPickings,
                categoryID: CategoryIDs.personal,
                publishedAt: Date().addingTimeInterval(-1 * 86400),
                isRead: false,
                readTimeMinutes: 10
            ),
            Article(
                title: "Creativity and Constraints",
                excerpt: "How limitations can actually enhance creative output and problem-solving.",
                sourceID: SourceIDs.waitButWhy,
                categoryID: CategoryIDs.personal,
                publishedAt: Date().addingTimeInterval(-3 * 86400),
                isRead: false,
                readTimeMinutes: 15
            ),

            // Additional mixed articles
            Article(
                title: "Understanding SwiftUI Performance",
                excerpt: "Profiling techniques and optimization strategies for smooth 60fps interfaces.",
                sourceID: SourceIDs.techCrunch,
                categoryID: CategoryIDs.techNews,
                publishedAt: Date().addingTimeInterval(-4 * 86400),
                isRead: true,
                readTimeMinutes: 16
            ),
            Article(
                title: "Accessibility-First Design",
                excerpt: "Building inclusive digital experiences that work for everyone, not just as an afterthought.",
                sourceID: SourceIDs.smashingMagazine,
                categoryID: CategoryIDs.design,
                publishedAt: Date().addingTimeInterval(-4 * 86400),
                isRead: false,
                readTimeMinutes: 12
            ),
            Article(
                title: "Managing Energy, Not Time",
                excerpt: "Why your focus and energy levels matter more than hours worked.",
                sourceID: SourceIDs.hbr,
                categoryID: CategoryIDs.work,
                publishedAt: Date().addingTimeInterval(-5 * 86400),
                isRead: false,
                readTimeMinutes: 8
            ),
            Article(
                title: "The Case for Boring Technology",
                excerpt: "Why proven, stable tech choices often beat the latest framework hype.",
                sourceID: SourceIDs.theVerge,
                categoryID: CategoryIDs.techNews,
                publishedAt: Date().addingTimeInterval(-5 * 86400),
                isRead: true,
                readTimeMinutes: 9
            ),
            Article(
                title: "Micro-Interactions That Delight",
                excerpt: "Small design touches that create memorable user experiences.",
                sourceID: SourceIDs.abduzeedo,
                categoryID: CategoryIDs.design,
                publishedAt: Date().addingTimeInterval(-6 * 86400),
                isRead: false,
                readTimeMinutes: 7
            ),
            Article(
                title: "Deep Work in the Age of AI",
                excerpt: "How to maintain focus and produce quality work alongside AI assistants.",
                sourceID: SourceIDs.lifehacker,
                categoryID: CategoryIDs.productivity,
                publishedAt: Date().addingTimeInterval(-6 * 86400),
                isRead: false,
                readTimeMinutes: 11
            ),
            Article(
                title: "The Future of Privacy",
                excerpt: "Emerging technologies and regulations that will shape how we protect personal data.",
                sourceID: SourceIDs.wired,
                categoryID: CategoryIDs.techNews,
                publishedAt: Date().addingTimeInterval(-7 * 86400),
                isRead: true,
                readTimeMinutes: 14
            )
        ]
    }

    @MainActor
    func refreshAllFeeds() async {
        let rssService = RSSService()
        var newArticles: [Article] = []
        var seen = Set<String>() // de-dupe key

        for source in sources {
            guard let url = URL(string: source.feedURL) else { continue }

            do {
                let parsed = try await rssService.fetchAndParseFeed(from: url)

                // ===== DEMO LOGGING (sample only) =====
                print("\n🛰 Fetching Feed:", source.name)
                print("   URL:", source.feedURL)
                print("   Articles Found:", parsed.count)

                for a in parsed.prefix(2) {
                    let t = a.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "nil"
                    let au = a.author?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "nil"
                    let lk = a.link?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "nil"

                    print("   • Title:", t)
                    print("     Author:", au)
                    print("     Date:", a.publicationDate?.description ?? "nil")
                    print("     Link:", lk)
                }
                print("-----")
                // =====================================

                let converted: [Article] = parsed.compactMap { p in
                    guard let title = p.title?.trimmingCharacters(in: .whitespacesAndNewlines),
                          !title.isEmpty else { return nil }

                    let rawExcerpt = p.description ?? ""
                    let excerpt = self.plainText(rawExcerpt)

                    // Better de-dupe: prefer link if present, else fall back to title
                    let linkKey = (p.link ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                    let key = linkKey.isEmpty
                        ? "\(source.id.uuidString)|\(title)"
                        : "\(source.id.uuidString)|\(linkKey)"
                    guard seen.insert(key).inserted else { return nil }

                    // Go back to “original” behavior:
                    // If the feed doesn't provide a date, just use now.
                    let published = p.publicationDate ?? Date()

                    // read-time estimate (200 wpm), clamped 1..30
                    let wordCount = excerpt.split { $0.isWhitespace || $0.isNewline }.count
                    let minutes = max(1, min(30, wordCount / 200))

                    return Article(
                        title: title,
                        excerpt: excerpt,
                        sourceID: source.id,
                        categoryID: source.categoryID,
                        publishedAt: published,
                        isRead: false,
                        readTimeMinutes: minutes
                    )
                }

                newArticles.append(contentsOf: converted)

            } catch {
                print("❌ Failed to fetch \(source.name): \(error)")
            }

            // throttle a bit to reduce rate-limit/blocks
            try? await Task.sleep(nanoseconds: 300_000_000)
        }

        newArticles.sort { $0.publishedAt > $1.publishedAt }

        if !newArticles.isEmpty {
            self.articles = newArticles
        } else {
            print("⚠️ refreshAllFeeds produced 0 articles; keeping existing articles.")
        }
    }

    // Put this helper anywhere inside MockDataService (private is fine)
    private func plainText(_ html: String) -> String {
        html
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }


    
    // MARK: - Query Methods

    func source(for id: UUID) -> Source? {
        sources.first { $0.id == id }
    }

    func category(for id: UUID) -> Category? {
        categories.first { $0.id == id }
    }

    func articlesForCategory(_ categoryID: UUID) -> [Article] {
        articles.filter { $0.categoryID == categoryID }
            .sorted { $0.publishedAt > $1.publishedAt }
    }

    func articlesForSource(_ sourceID: UUID) -> [Article] {
        articles.filter { $0.sourceID == sourceID }
            .sorted { $0.publishedAt > $1.publishedAt }
    }

    func unreadCountForCategory(_ categoryID: UUID) -> Int {
        articles.filter { $0.categoryID == categoryID && !$0.isRead }.count
    }

    func unreadCountForSource(_ sourceID: UUID) -> Int {
        articles.filter { $0.sourceID == sourceID && !$0.isRead }.count
    }

    func bookmarkedArticles() -> [Article] {
        articles.filter { $0.isBookmarked }
            .sorted { $0.publishedAt > $1.publishedAt }
    }

    func totalUnreadCount() -> Int {
        articles.filter { !$0.isRead }.count
    }
}

// MARK: - Static UUIDs for Relationships

private enum CategoryIDs {
    static let techNews = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
    static let design = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
    static let work = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!
    static let productivity = UUID(uuidString: "44444444-4444-4444-4444-444444444444")!
    static let personal = UUID(uuidString: "55555555-5555-5555-5555-555555555555")!
}

private enum SourceIDs {
    // Tech News
    static let techCrunch = UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")!
    static let theVerge = UUID(uuidString: "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb")!
    static let arstechnica = UUID(uuidString: "cccccccc-cccc-cccc-cccc-cccccccccccc")!
    static let wired = UUID(uuidString: "dddddddd-dddd-dddd-dddd-dddddddddddd")!

    // Design
    static let smashingMagazine = UUID(uuidString: "eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee")!
    static let designernews = UUID(uuidString: "ffffffff-ffff-ffff-ffff-ffffffffffff")!
    static let abduzeedo = UUID(uuidString: "11111111-aaaa-aaaa-aaaa-aaaaaaaaaaaa")!

    // Work
    static let hbr = UUID(uuidString: "22222222-bbbb-bbbb-bbbb-bbbbbbbbbbbb")!
    static let fastCompany = UUID(uuidString: "33333333-cccc-cccc-cccc-cccccccccccc")!

    // Productivity
    static let lifehacker = UUID(uuidString: "44444444-dddd-dddd-dddd-dddddddddddd")!
    static let zenHabits = UUID(uuidString: "55555555-eeee-eeee-eeee-eeeeeeeeeeee")!

    // Personal
    static let brainPickings = UUID(uuidString: "66666666-ffff-ffff-ffff-ffffffffffff")!
    static let waitButWhy = UUID(uuidString: "77777777-aaaa-bbbb-cccc-dddddddddddd")!
}
