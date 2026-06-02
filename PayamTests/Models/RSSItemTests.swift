//
//  RSSItemTests.swift
//  PayamTests
//

import XCTest
@testable import Payam

final class RSSItemTests: XCTestCase {

    func test_init_setsAllProperties() {
        let id = UUID()
        let url = URL(string: "https://example.com/article")!
        let date = Date()

        let item = RSSItem(
            id: id,
            title: "Test Title",
            author: "Author Name",
            publishDate: date,
            summary: "A brief summary",
            sourceURL: url,
            feedName: "Test Feed"
        )

        XCTAssertEqual(item.id, id)
        XCTAssertEqual(item.title, "Test Title")
        XCTAssertEqual(item.author, "Author Name")
        XCTAssertEqual(item.publishDate, date)
        XCTAssertEqual(item.summary, "A brief summary")
        XCTAssertEqual(item.sourceURL, url)
        XCTAssertEqual(item.feedName, "Test Feed")
    }

    func test_init_optionalFieldsNil() {
        let item = RSSItem(
            id: UUID(),
            title: "Title",
            author: nil,
            publishDate: nil,
            summary: nil,
            sourceURL: URL(string: "https://example.com")!,
            feedName: "Feed"
        )

        XCTAssertNil(item.author)
        XCTAssertNil(item.publishDate)
        XCTAssertNil(item.summary)
    }

    func test_hashable_sameIDSameHash() {
        let id = UUID()
        let a = RSSItem(id: id, title: "A", author: nil, publishDate: nil, summary: nil,
                        sourceURL: URL(string: "https://a.com")!, feedName: "A")
        let b = RSSItem(id: id, title: "B", author: nil, publishDate: nil, summary: nil,
                        sourceURL: URL(string: "https://b.com")!, feedName: "B")
        XCTAssertEqual(a.hashValue, b.hashValue)
    }

    func test_identifiable_differentIDs() {
        let a = RSSItem(id: UUID(), title: "A", author: nil, publishDate: nil, summary: nil,
                        sourceURL: URL(string: "https://a.com")!, feedName: "A")
        let b = RSSItem(id: UUID(), title: "A", author: nil, publishDate: nil, summary: nil,
                        sourceURL: URL(string: "https://a.com")!, feedName: "A")
        XCTAssertNotEqual(a.id, b.id)
    }
}
