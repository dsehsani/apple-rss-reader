//
//  VideoDetectorTests.swift
//  PayamTests
//

import XCTest
@testable import Payam

final class VideoDetectorTests: XCTestCase {

    // MARK: - Vimeo Detection

    func test_detect_vimeo_standardURL() {
        let url = URL(string: "https://vimeo.com/12345")!
        let result = VideoDetector.detect(url)
        XCTAssertEqual(result, .vimeo(id: "12345"))
    }

    func test_detect_vimeo_wwwSubdomain() {
        let url = URL(string: "https://www.vimeo.com/67890")!
        let result = VideoDetector.detect(url)
        XCTAssertEqual(result, .vimeo(id: "67890"))
    }

    func test_detect_vimeo_playerEmbed() {
        let url = URL(string: "https://player.vimeo.com/video/12345")!
        let result = VideoDetector.detect(url)
        XCTAssertEqual(result, .vimeo(id: "12345"))
    }

    func test_detect_vimeo_playerEmbed_invalidPath() {
        let url = URL(string: "https://player.vimeo.com/other/12345")!
        let result = VideoDetector.detect(url)
        XCTAssertNil(result)
    }

    func test_detect_vimeo_nonNumericPath() {
        let url = URL(string: "https://vimeo.com/blog/post")!
        let result = VideoDetector.detect(url)
        XCTAssertNil(result)
    }

    func test_detect_vimeo_withTrailingPath() {
        let url = URL(string: "https://vimeo.com/12345/abcdef")!
        let result = VideoDetector.detect(url)
        XCTAssertEqual(result, .vimeo(id: "12345"))
    }

    // MARK: - Direct File Detection

    func test_detect_mp4() {
        let url = URL(string: "https://cdn.example.com/video.mp4")!
        if case .directFile(let fileURL) = VideoDetector.detect(url)! {
            XCTAssertEqual(fileURL, url)
        } else {
            XCTFail("Expected directFile")
        }
    }

    func test_detect_webm() {
        let url = URL(string: "https://cdn.example.com/clip.webm")!
        XCTAssertNotNil(VideoDetector.detect(url))
    }

    func test_detect_mov() {
        let url = URL(string: "https://cdn.example.com/movie.mov")!
        XCTAssertNotNil(VideoDetector.detect(url))
    }

    func test_detect_m4v() {
        let url = URL(string: "https://cdn.example.com/trailer.m4v")!
        XCTAssertNotNil(VideoDetector.detect(url))
    }

    // MARK: - Non-Video URLs

    func test_detect_htmlPage_returnsNil() {
        let url = URL(string: "https://example.com/article.html")!
        XCTAssertNil(VideoDetector.detect(url))
    }

    func test_detect_imageFile_returnsNil() {
        let url = URL(string: "https://example.com/photo.jpg")!
        XCTAssertNil(VideoDetector.detect(url))
    }

    func test_detect_youtubeURL_returnsNil() {
        // VideoDetector intentionally excludes YouTube
        let url = URL(string: "https://youtube.com/watch?v=abc123")!
        XCTAssertNil(VideoDetector.detect(url))
    }

    // MARK: - isVideoURL Convenience

    func test_isVideoURL_validVimeo_true() {
        XCTAssertTrue(VideoDetector.isVideoURL("https://vimeo.com/12345"))
    }

    func test_isVideoURL_normalPage_false() {
        XCTAssertFalse(VideoDetector.isVideoURL("https://example.com/news"))
    }

    func test_isVideoURL_invalidString_false() {
        XCTAssertFalse(VideoDetector.isVideoURL("not a url"))
    }
}
