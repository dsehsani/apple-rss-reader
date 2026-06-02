//
//  ContentNodeTests.swift
//  PayamTests
//

import XCTest
@testable import Payam

final class ContentNodeTests: XCTestCase {

    // MARK: - Codable

    func test_codable_heading() throws {
        let node = ContentNode.heading(level: 2, text: "Hello World")
        let data = try JSONEncoder().encode(node)
        let decoded = try JSONDecoder().decode(ContentNode.self, from: data)

        if case .heading(let level, let text) = decoded {
            XCTAssertEqual(level, 2)
            XCTAssertEqual(text, "Hello World")
        } else {
            XCTFail("Expected heading")
        }
    }

    func test_codable_paragraph() throws {
        let node = ContentNode.paragraph(text: "Body text here.")
        let data = try JSONEncoder().encode(node)
        let decoded = try JSONDecoder().decode(ContentNode.self, from: data)

        if case .paragraph(let text) = decoded {
            XCTAssertEqual(text, "Body text here.")
        } else {
            XCTFail("Expected paragraph")
        }
    }

    func test_codable_image_withCaption() throws {
        let node = ContentNode.image(url: URL(string: "https://example.com/img.jpg")!, caption: "A photo")
        let data = try JSONEncoder().encode(node)
        let decoded = try JSONDecoder().decode(ContentNode.self, from: data)

        if case .image(let url, let caption) = decoded {
            XCTAssertEqual(url.absoluteString, "https://example.com/img.jpg")
            XCTAssertEqual(caption, "A photo")
        } else {
            XCTFail("Expected image")
        }
    }

    func test_codable_image_nilCaption() throws {
        let node = ContentNode.image(url: URL(string: "https://example.com/img.jpg")!, caption: nil)
        let data = try JSONEncoder().encode(node)
        let decoded = try JSONDecoder().decode(ContentNode.self, from: data)

        if case .image(_, let caption) = decoded {
            XCTAssertNil(caption)
        } else {
            XCTFail("Expected image")
        }
    }

    func test_codable_blockquote() throws {
        let node = ContentNode.blockquote(text: "To be or not to be")
        let data = try JSONEncoder().encode(node)
        let decoded = try JSONDecoder().decode(ContentNode.self, from: data)

        if case .blockquote(let text) = decoded {
            XCTAssertEqual(text, "To be or not to be")
        } else {
            XCTFail("Expected blockquote")
        }
    }

    func test_codable_list_ordered() throws {
        let node = ContentNode.list(items: ["First", "Second", "Third"], ordered: true)
        let data = try JSONEncoder().encode(node)
        let decoded = try JSONDecoder().decode(ContentNode.self, from: data)

        if case .list(let items, let ordered) = decoded {
            XCTAssertEqual(items, ["First", "Second", "Third"])
            XCTAssertTrue(ordered)
        } else {
            XCTFail("Expected list")
        }
    }

    func test_codable_codeBlock() throws {
        let node = ContentNode.codeBlock(text: "let x = 42")
        let data = try JSONEncoder().encode(node)
        let decoded = try JSONDecoder().decode(ContentNode.self, from: data)

        if case .codeBlock(let text) = decoded {
            XCTAssertEqual(text, "let x = 42")
        } else {
            XCTFail("Expected codeBlock")
        }
    }

    func test_codable_table() throws {
        let node = ContentNode.table(headers: ["Name", "Age"], rows: [["Alice", "30"], ["Bob", "25"]])
        let data = try JSONEncoder().encode(node)
        let decoded = try JSONDecoder().decode(ContentNode.self, from: data)

        if case .table(let headers, let rows) = decoded {
            XCTAssertEqual(headers, ["Name", "Age"])
            XCTAssertEqual(rows.count, 2)
        } else {
            XCTFail("Expected table")
        }
    }

    func test_codable_videoEmbed() throws {
        let node = ContentNode.videoEmbed(
            url: URL(string: "https://youtube.com/watch?v=abc")!,
            thumbnailURL: URL(string: "https://img.youtube.com/vi/abc/hqdefault.jpg")
        )
        let data = try JSONEncoder().encode(node)
        let decoded = try JSONDecoder().decode(ContentNode.self, from: data)

        if case .videoEmbed(let url, let thumbnailURL) = decoded {
            XCTAssertEqual(url.absoluteString, "https://youtube.com/watch?v=abc")
            XCTAssertNotNil(thumbnailURL)
        } else {
            XCTFail("Expected videoEmbed")
        }
    }
}
