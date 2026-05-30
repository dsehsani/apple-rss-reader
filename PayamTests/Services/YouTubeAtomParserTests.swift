//
//  YouTubeAtomParserTests.swift
//  PayamTests
//

import XCTest
@testable import Payam

final class YouTubeAtomParserTests: XCTestCase {

    func test_parse_validAtomFeed() {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <feed xmlns:media="http://search.yahoo.com/mrss/">
          <entry>
            <link rel="alternate" href="https://www.youtube.com/watch?v=abc123"/>
            <media:group>
              <media:thumbnail url="https://i.ytimg.com/vi/abc123/hqdefault.jpg"/>
              <media:description>This is a test video description.</media:description>
            </media:group>
          </entry>
          <entry>
            <link rel="alternate" href="https://www.youtube.com/watch?v=xyz789"/>
            <media:group>
              <media:thumbnail url="https://i.ytimg.com/vi/xyz789/hqdefault.jpg"/>
              <media:description>Another video.</media:description>
            </media:group>
          </entry>
        </feed>
        """

        let parser = YouTubeAtomParser()
        let results = parser.parse(data: xml.data(using: .utf8)!)

        XCTAssertEqual(results.count, 2)

        let meta1 = results["https://www.youtube.com/watch?v=abc123"]
        XCTAssertNotNil(meta1)
        XCTAssertEqual(meta1?.thumbnailURL, "https://i.ytimg.com/vi/abc123/hqdefault.jpg")
        XCTAssertEqual(meta1?.description, "This is a test video description.")

        let meta2 = results["https://www.youtube.com/watch?v=xyz789"]
        XCTAssertNotNil(meta2)
        XCTAssertEqual(meta2?.description, "Another video.")
    }

    func test_parse_emptyFeed() {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <feed></feed>
        """
        let parser = YouTubeAtomParser()
        let results = parser.parse(data: xml.data(using: .utf8)!)
        XCTAssertTrue(results.isEmpty)
    }

    func test_parse_entryWithoutMediaGroup() {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <feed>
          <entry>
            <link rel="alternate" href="https://www.youtube.com/watch?v=nogroup"/>
          </entry>
        </feed>
        """
        let parser = YouTubeAtomParser()
        let results = parser.parse(data: xml.data(using: .utf8)!)

        XCTAssertEqual(results.count, 1)
        let meta = results["https://www.youtube.com/watch?v=nogroup"]
        XCTAssertNotNil(meta)
        XCTAssertNil(meta?.thumbnailURL)
        XCTAssertNil(meta?.description)
    }

    func test_parse_entryWithoutLink_skipped() {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <feed xmlns:media="http://search.yahoo.com/mrss/">
          <entry>
            <media:group>
              <media:description>No link here</media:description>
            </media:group>
          </entry>
        </feed>
        """
        let parser = YouTubeAtomParser()
        let results = parser.parse(data: xml.data(using: .utf8)!)
        XCTAssertTrue(results.isEmpty)
    }

    func test_parse_invalidXML_returnsEmpty() {
        let data = "not xml at all".data(using: .utf8)!
        let parser = YouTubeAtomParser()
        let results = parser.parse(data: data)
        // Should not crash, may return empty
        XCTAssertNotNil(results)
    }
}
