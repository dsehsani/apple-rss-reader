//
//  YouTubeServiceTests.swift
//  PayamTests
//

import XCTest
@testable import Payam

final class YouTubeServiceTests: XCTestCase {

    // MARK: - isYouTubeURL

    func test_isYouTubeURL_standard() {
        XCTAssertTrue(YouTubeService.isYouTubeURL(URL(string: "https://youtube.com/watch?v=abc")!))
    }

    func test_isYouTubeURL_www() {
        XCTAssertTrue(YouTubeService.isYouTubeURL(URL(string: "https://www.youtube.com/watch?v=abc")!))
    }

    func test_isYouTubeURL_mobile() {
        XCTAssertTrue(YouTubeService.isYouTubeURL(URL(string: "https://m.youtube.com/watch?v=abc")!))
    }

    func test_isYouTubeURL_shortener() {
        XCTAssertTrue(YouTubeService.isYouTubeURL(URL(string: "https://youtu.be/abc123")!))
    }

    func test_isYouTubeURL_nonYouTube_false() {
        XCTAssertFalse(YouTubeService.isYouTubeURL(URL(string: "https://vimeo.com/12345")!))
    }

    // MARK: - Route

    func test_route_watchURL_video() {
        let url = URL(string: "https://www.youtube.com/watch?v=dQw4w9WgXcQ")!
        let result = YouTubeService.route(for: url)
        XCTAssertEqual(result, .video(id: "dQw4w9WgXcQ"))
    }

    func test_route_shortURL_video() {
        let url = URL(string: "https://youtu.be/dQw4w9WgXcQ")!
        let result = YouTubeService.route(for: url)
        XCTAssertEqual(result, .video(id: "dQw4w9WgXcQ"))
    }

    func test_route_shortsURL_short() {
        let url = URL(string: "https://www.youtube.com/shorts/abc123")!
        let result = YouTubeService.route(for: url)
        XCTAssertEqual(result, .short(id: "abc123"))
    }

    func test_route_playlistURL_playlist() {
        let url = URL(string: "https://www.youtube.com/playlist?list=PLrAXtmErZgOeiKm4sgNOknGvNjby9efdf")!
        let result = YouTubeService.route(for: url)
        XCTAssertEqual(result, .playlist(id: "PLrAXtmErZgOeiKm4sgNOknGvNjby9efdf"))
    }

    func test_route_channelURL_unknown() {
        let url = URL(string: "https://www.youtube.com/channel/UCxxxxxxxxxx")!
        let result = YouTubeService.route(for: url)
        XCTAssertEqual(result, .unknown)
    }

    func test_route_nonYouTube_unknown() {
        let url = URL(string: "https://example.com/page")!
        let result = YouTubeService.route(for: url)
        XCTAssertEqual(result, .unknown)
    }

    func test_route_watchWithList_stillVideo() {
        let url = URL(string: "https://www.youtube.com/watch?v=abc&list=PLxxx")!
        let result = YouTubeService.route(for: url)
        XCTAssertEqual(result, .video(id: "abc"))
    }

    func test_route_emptyShortID_unknown() {
        let url = URL(string: "https://www.youtube.com/shorts/")!
        let result = YouTubeService.route(for: url)
        XCTAssertEqual(result, .unknown)
    }

    // MARK: - Content Kind

    func test_contentKind_videoURL() {
        let kind = YouTubeService.contentKind(forArticleURL: "https://www.youtube.com/watch?v=abc")
        XCTAssertEqual(kind, .video)
    }

    func test_contentKind_shortURL() {
        let kind = YouTubeService.contentKind(forArticleURL: "https://www.youtube.com/shorts/abc")
        XCTAssertEqual(kind, .short)
    }

    func test_contentKind_playlistURL() {
        let kind = YouTubeService.contentKind(forArticleURL: "https://www.youtube.com/playlist?list=PLxxx")
        XCTAssertEqual(kind, .playlist)
    }

    func test_contentKind_nonYouTubeURL_nil() {
        let kind = YouTubeService.contentKind(forArticleURL: "https://example.com/article")
        XCTAssertNil(kind)
    }

    // MARK: - Video ID Extraction

    func test_videoID_fromWatch() {
        XCTAssertEqual(YouTubeService.videoID(from: "https://www.youtube.com/watch?v=abc123"), "abc123")
    }

    func test_videoID_fromShort() {
        XCTAssertEqual(YouTubeService.videoID(from: "https://www.youtube.com/shorts/xyz789"), "xyz789")
    }

    func test_videoID_fromPlaylist_nil() {
        XCTAssertNil(YouTubeService.videoID(from: "https://www.youtube.com/playlist?list=PLxxx"))
    }

    // MARK: - Playlist ID Extraction

    func test_playlistID_fromPlaylist() {
        XCTAssertEqual(
            YouTubeService.playlistID(from: "https://www.youtube.com/playlist?list=PLxxx"),
            "PLxxx"
        )
    }

    func test_playlistID_fromVideo_nil() {
        XCTAssertNil(YouTubeService.playlistID(from: "https://www.youtube.com/watch?v=abc"))
    }

    // MARK: - Thumbnail URL

    func test_thumbnailURL_validVideoID() {
        let url = YouTubeService.thumbnailURL(videoID: "abc123")
        XCTAssertEqual(url?.absoluteString, "https://img.youtube.com/vi/abc123/hqdefault.jpg")
    }

    // MARK: - isYouTubeContentURL

    func test_isYouTubeContentURL_video() {
        XCTAssertTrue(YouTubeService.isYouTubeContentURL("https://www.youtube.com/watch?v=abc"))
    }

    func test_isYouTubeContentURL_short() {
        XCTAssertTrue(YouTubeService.isYouTubeContentURL("https://www.youtube.com/shorts/abc"))
    }

    func test_isYouTubeContentURL_playlist() {
        XCTAssertTrue(YouTubeService.isYouTubeContentURL("https://www.youtube.com/playlist?list=PLxxx"))
    }

    func test_isYouTubeContentURL_channel_false() {
        XCTAssertFalse(YouTubeService.isYouTubeContentURL("https://www.youtube.com/channel/UCxxx"))
    }

    // MARK: - isYouTubeVideoOrShortURL

    func test_isYouTubeVideoOrShortURL_video_true() {
        XCTAssertTrue(YouTubeService.isYouTubeVideoOrShortURL("https://www.youtube.com/watch?v=abc"))
    }

    func test_isYouTubeVideoOrShortURL_playlist_false() {
        XCTAssertFalse(YouTubeService.isYouTubeVideoOrShortURL("https://www.youtube.com/playlist?list=PLxxx"))
    }

    // MARK: - YouTubeContentKind Display

    func test_contentKind_displayNames() {
        XCTAssertEqual(YouTubeService.YouTubeContentKind.video.displayName, "Videos")
        XCTAssertEqual(YouTubeService.YouTubeContentKind.short.displayName, "Shorts")
        XCTAssertEqual(YouTubeService.YouTubeContentKind.playlist.displayName, "Playlists")
    }

    func test_contentKind_icons() {
        XCTAssertFalse(YouTubeService.YouTubeContentKind.video.icon.isEmpty)
        XCTAssertFalse(YouTubeService.YouTubeContentKind.short.icon.isEmpty)
        XCTAssertFalse(YouTubeService.YouTubeContentKind.playlist.icon.isEmpty)
    }
}
