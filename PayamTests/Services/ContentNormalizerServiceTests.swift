//
//  ContentNormalizerServiceTests.swift
//  PayamTests
//

import XCTest
@testable import Payam

final class ContentNormalizerServiceTests: XCTestCase {

    let service = ContentNormalizerService()

    // MARK: - Helpers

    private func normalize(_ html: String) throws -> [ContentNode] {
        let content = ReadableContent(
            title: "Test",
            byline: nil,
            content: html,
            excerpt: nil,
            heroImageURL: nil
        )
        return try service.normalize(content: content)
    }

    // MARK: - Headings

    func test_normalize_heading_h1() throws {
        let nodes = try normalize("<h1>Main Title</h1>")
        XCTAssertEqual(nodes.count, 1)
        if case .heading(let level, let text) = nodes[0] {
            XCTAssertEqual(level, 1)
            XCTAssertEqual(text, "Main Title")
        } else {
            XCTFail("Expected heading")
        }
    }

    func test_normalize_heading_h3() throws {
        let nodes = try normalize("<h3>Subsection</h3>")
        if case .heading(let level, _) = nodes[0] {
            XCTAssertEqual(level, 3)
        } else {
            XCTFail("Expected heading")
        }
    }

    // MARK: - Paragraphs

    func test_normalize_paragraph() throws {
        let nodes = try normalize("<p>Hello world, this is a paragraph.</p>")
        XCTAssertEqual(nodes.count, 1)
        if case .paragraph(let text) = nodes[0] {
            XCTAssertEqual(text, "Hello world, this is a paragraph.")
        } else {
            XCTFail("Expected paragraph")
        }
    }

    func test_normalize_emptyParagraph_skipped() throws {
        let nodes = try normalize("<p>   </p>")
        XCTAssertTrue(nodes.isEmpty)
    }

    // MARK: - Images

    func test_normalize_image_httpsOnly() throws {
        let nodes = try normalize("""
        <img src="https://example.com/photo.jpg" alt="A nice photo"/>
        """)
        XCTAssertEqual(nodes.count, 1)
        if case .image(let url, let caption) = nodes[0] {
            XCTAssertEqual(url.absoluteString, "https://example.com/photo.jpg")
            XCTAssertEqual(caption, "A nice photo")
        } else {
            XCTFail("Expected image")
        }
    }

    func test_normalize_image_noAlt_nilCaption() throws {
        let nodes = try normalize("<img src=\"https://example.com/img.jpg\"/>")
        if case .image(_, let caption) = nodes[0] {
            XCTAssertNil(caption)
        } else {
            XCTFail("Expected image")
        }
    }

    func test_normalize_image_logoAlt_filtered() throws {
        let nodes = try normalize("<img src=\"https://example.com/img.jpg\" alt=\"Company Logo\"/>")
        XCTAssertTrue(nodes.isEmpty, "Logo images should be filtered out")
    }

    func test_normalize_image_avatarDomain_filtered() throws {
        let nodes = try normalize("<img src=\"https://secure.gravatar.com/avatar/abc123\" alt=\"Author\"/>")
        XCTAssertTrue(nodes.isEmpty, "Gravatar avatars should be filtered out")
    }

    // MARK: - Blockquotes

    func test_normalize_blockquote() throws {
        let nodes = try normalize("<blockquote>A wise saying.</blockquote>")
        if case .blockquote(let text) = nodes[0] {
            XCTAssertEqual(text, "A wise saying.")
        } else {
            XCTFail("Expected blockquote")
        }
    }

    // MARK: - Lists

    func test_normalize_unorderedList() throws {
        let nodes = try normalize("<ul><li>Apple</li><li>Banana</li></ul>")
        if case .list(let items, let ordered) = nodes[0] {
            XCTAssertEqual(items, ["Apple", "Banana"])
            XCTAssertFalse(ordered)
        } else {
            XCTFail("Expected unordered list")
        }
    }

    func test_normalize_orderedList() throws {
        let nodes = try normalize("<ol><li>First</li><li>Second</li></ol>")
        if case .list(let items, let ordered) = nodes[0] {
            XCTAssertEqual(items, ["First", "Second"])
            XCTAssertTrue(ordered)
        } else {
            XCTFail("Expected ordered list")
        }
    }

    // MARK: - Code Blocks

    func test_normalize_codeBlock() throws {
        let nodes = try normalize("<pre><code>let x = 42</code></pre>")
        if case .codeBlock(let text) = nodes[0] {
            XCTAssertEqual(text, "let x = 42")
        } else {
            XCTFail("Expected codeBlock")
        }
    }

    // MARK: - Tables

    func test_normalize_table() throws {
        let html = """
        <table>
            <tr><th>Name</th><th>Age</th></tr>
            <tr><td>Alice</td><td>30</td></tr>
            <tr><td>Bob</td><td>25</td></tr>
        </table>
        """
        let nodes = try normalize(html)
        if case .table(let headers, let rows) = nodes[0] {
            XCTAssertEqual(headers, ["Name", "Age"])
            XCTAssertEqual(rows.count, 2)
            XCTAssertEqual(rows[0], ["Alice", "30"])
        } else {
            XCTFail("Expected table")
        }
    }

    // MARK: - Video Embeds

    func test_normalize_youtubeIframe() throws {
        let html = "<iframe src=\"https://www.youtube.com/embed/dQw4w9WgXcQ\"></iframe>"
        let nodes = try normalize(html)
        if case .videoEmbed(let url, let thumbnail) = nodes[0] {
            // Should be normalized to watch URL
            XCTAssertEqual(url.absoluteString, "https://www.youtube.com/watch?v=dQw4w9WgXcQ")
            XCTAssertNotNil(thumbnail)
        } else {
            XCTFail("Expected videoEmbed")
        }
    }

    func test_normalize_nonVideoIframe_skipped() throws {
        let html = "<iframe src=\"https://example.com/widget\"></iframe>"
        let nodes = try normalize(html)
        // Non-video iframe hosts are treated as containers, not video embeds
        XCTAssertTrue(nodes.isEmpty)
    }

    // MARK: - Noise Removal

    func test_normalize_scriptTags_stripped() throws {
        let html = "<p>Real content</p><script>alert('xss')</script>"
        let nodes = try normalize(html)
        XCTAssertEqual(nodes.count, 1)
        if case .paragraph(let text) = nodes[0] {
            XCTAssertEqual(text, "Real content")
        }
    }

    func test_normalize_adPlaceholder_stripped() throws {
        let nodes = try normalize("<p>Advertisement</p>")
        XCTAssertTrue(nodes.isEmpty)
    }

    func test_normalize_videoPlayerArtifact_stripped() throws {
        let nodes = try normalize("<p>Current Time 0:00</p>")
        XCTAssertTrue(nodes.isEmpty)
    }

    // MARK: - isVideoHost

    func test_isVideoHost_youtube() {
        let url = URL(string: "https://www.youtube.com/embed/abc")!
        XCTAssertTrue(ContentNormalizerService.isVideoHost(url))
    }

    func test_isVideoHost_vimeo() {
        let url = URL(string: "https://player.vimeo.com/video/123")!
        XCTAssertTrue(ContentNormalizerService.isVideoHost(url))
    }

    func test_isVideoHost_bbc() {
        let url = URL(string: "https://player.bbc.com/video/123")!
        XCTAssertTrue(ContentNormalizerService.isVideoHost(url))
    }

    func test_isVideoHost_unknown_false() {
        let url = URL(string: "https://example.com/video")!
        XCTAssertFalse(ContentNormalizerService.isVideoHost(url))
    }

    // MARK: - normalizeVideoURL

    func test_normalizeVideoURL_youtubeEmbed_toWatch() {
        let embed = URL(string: "https://www.youtube.com/embed/abc123")!
        let result = ContentNormalizerService.normalizeVideoURL(embed)
        XCTAssertEqual(result.absoluteString, "https://www.youtube.com/watch?v=abc123")
    }

    func test_normalizeVideoURL_nonYouTube_unchanged() {
        let url = URL(string: "https://vimeo.com/12345")!
        let result = ContentNormalizerService.normalizeVideoURL(url)
        XCTAssertEqual(result, url)
    }

    // MARK: - videoThumbnail

    func test_videoThumbnail_youtubeEmbed() {
        let url = URL(string: "https://www.youtube.com/embed/abc123")!
        let thumb = ContentNormalizerService.videoThumbnail(for: url)
        XCTAssertEqual(thumb?.absoluteString, "https://img.youtube.com/vi/abc123/hqdefault.jpg")
    }

    func test_videoThumbnail_nonYouTube_nil() {
        let url = URL(string: "https://vimeo.com/12345")!
        XCTAssertNil(ContentNormalizerService.videoThumbnail(for: url))
    }

    // MARK: - Figure with Video

    func test_normalize_figureWithYouTubeIframe() throws {
        let html = """
        <figure>
            <iframe src="https://www.youtube.com/embed/xyz789"></iframe>
        </figure>
        """
        let nodes = try normalize(html)
        XCTAssertEqual(nodes.count, 1)
        if case .videoEmbed(let url, _) = nodes[0] {
            XCTAssertEqual(url.absoluteString, "https://www.youtube.com/watch?v=xyz789")
        } else {
            XCTFail("Expected videoEmbed from figure")
        }
    }

    // MARK: - Figure with Image + Caption

    func test_normalize_figureWithImgAndCaption() throws {
        let html = """
        <figure>
            <img src="https://example.com/photo.jpg" alt="Alt text"/>
            <figcaption>A beautiful sunset</figcaption>
        </figure>
        """
        let nodes = try normalize(html)
        if case .image(_, let caption) = nodes[0] {
            XCTAssertEqual(caption, "A beautiful sunset")
        } else {
            XCTFail("Expected image with caption")
        }
    }
}
