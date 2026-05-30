//
//  PaywallDetectorTests.swift
//  PayamTests
//

import XCTest
@testable import Payam

final class PaywallDetectorTests: XCTestCase {

    // MARK: - Domain Allow-List

    func test_isPaywalled_knownDomain_nytimes() {
        let article = TestFactory.makeExtractedArticle(sourceURL: "https://www.nytimes.com/article")
        XCTAssertTrue(PaywallDetector.isPaywalled(article: article))
    }

    func test_isPaywalled_knownDomain_wsj() {
        let article = TestFactory.makeExtractedArticle(sourceURL: "https://wsj.com/markets/stocks")
        XCTAssertTrue(PaywallDetector.isPaywalled(article: article))
    }

    func test_isPaywalled_knownDomain_bloomberg() {
        let article = TestFactory.makeExtractedArticle(sourceURL: "https://www.bloomberg.com/news")
        XCTAssertTrue(PaywallDetector.isPaywalled(article: article))
    }

    func test_isPaywalled_knownDomain_medium() {
        let article = TestFactory.makeExtractedArticle(sourceURL: "https://medium.com/@user/article")
        XCTAssertTrue(PaywallDetector.isPaywalled(article: article))
    }

    func test_isPaywalled_unknownDomain_free() {
        let article = TestFactory.makeExtractedArticle(sourceURL: "https://example.com/article")
        XCTAssertFalse(PaywallDetector.isPaywalled(article: article))
    }

    func test_isPaywalled_subdomain_matches() {
        let article = TestFactory.makeExtractedArticle(sourceURL: "https://www.ft.com/article")
        XCTAssertTrue(PaywallDetector.isPaywalled(article: article))
    }

    // MARK: - Body Phrase Detection

    func test_isPaywalled_subscribeToContinue() {
        let article = TestFactory.makeExtractedArticle(
            sourceURL: "https://example.com/article",
            nodes: [.paragraph(text: "Please subscribe to continue reading this article.")]
        )
        XCTAssertTrue(PaywallDetector.isPaywalled(article: article))
    }

    func test_isPaywalled_subscribersOnly() {
        let article = TestFactory.makeExtractedArticle(
            sourceURL: "https://example.com/article",
            nodes: [.paragraph(text: "This content is for subscribers only.")]
        )
        XCTAssertTrue(PaywallDetector.isPaywalled(article: article))
    }

    func test_isPaywalled_freeArticleLimit() {
        let article = TestFactory.makeExtractedArticle(
            sourceURL: "https://example.com/article",
            nodes: [.paragraph(text: "You've reached your free article limit this month.")]
        )
        XCTAssertTrue(PaywallDetector.isPaywalled(article: article))
    }

    func test_isPaywalled_signInToRead() {
        let article = TestFactory.makeExtractedArticle(
            sourceURL: "https://example.com/article",
            nodes: [.paragraph(text: "Sign in to read the full article.")]
        )
        XCTAssertTrue(PaywallDetector.isPaywalled(article: article))
    }

    func test_isPaywalled_noPaywallPhrases_free() {
        let article = TestFactory.makeExtractedArticle(
            sourceURL: "https://example.com/article",
            nodes: [
                .paragraph(text: "This is a normal article about technology."),
                .paragraph(text: "It discusses various topics without any paywall restrictions."),
            ]
        )
        XCTAssertFalse(PaywallDetector.isPaywalled(article: article))
    }

    func test_isPaywalled_headingContainsPhrase() {
        let article = TestFactory.makeExtractedArticle(
            sourceURL: "https://example.com/article",
            nodes: [.heading(level: 2, text: "Members only content")]
        )
        XCTAssertTrue(PaywallDetector.isPaywalled(article: article))
    }

    func test_isPaywalled_blockquoteContainsPhrase() {
        let article = TestFactory.makeExtractedArticle(
            sourceURL: "https://example.com/article",
            nodes: [.blockquote(text: "Already a subscriber? Sign in to read.")]
        )
        XCTAssertTrue(PaywallDetector.isPaywalled(article: article))
    }

    // MARK: - Truncation Signal

    func test_isPaywalled_truncated_ellipsis() {
        let article = TestFactory.makeExtractedArticle(
            sourceURL: "https://example.com/article",
            nodes: [.paragraph(text: "Short preview of the article content that ends abruptly...")]
        )
        XCTAssertTrue(PaywallDetector.isPaywalled(article: article))
    }

    func test_isPaywalled_truncated_readMore() {
        let article = TestFactory.makeExtractedArticle(
            sourceURL: "https://example.com/article",
            nodes: [.paragraph(text: "Brief intro. Click here to read more")]
        )
        XCTAssertTrue(PaywallDetector.isPaywalled(article: article))
    }

    func test_isPaywalled_longContent_notTruncated() {
        // Over 150 words should not trigger truncation signal
        let longText = Array(repeating: "word", count: 200).joined(separator: " ")
        let article = TestFactory.makeExtractedArticle(
            sourceURL: "https://example.com/article",
            nodes: [.paragraph(text: longText + "...")]
        )
        XCTAssertFalse(PaywallDetector.isPaywalled(article: article))
    }

    func test_isPaywalled_emptyNodes() {
        let article = TestFactory.makeExtractedArticle(
            sourceURL: "https://example.com/article",
            nodes: []
        )
        XCTAssertFalse(PaywallDetector.isPaywalled(article: article))
    }

    // MARK: - URL-only convenience

    func test_isPaywalled_urlString_knownDomain() {
        XCTAssertTrue(PaywallDetector.isPaywalled(urlString: "https://www.nytimes.com/2024/article"))
    }

    func test_isPaywalled_urlString_unknownDomain() {
        XCTAssertFalse(PaywallDetector.isPaywalled(urlString: "https://example.com/article"))
    }

    func test_isPaywalled_urlString_invalidURL() {
        XCTAssertFalse(PaywallDetector.isPaywalled(urlString: "not a url"))
    }
}
