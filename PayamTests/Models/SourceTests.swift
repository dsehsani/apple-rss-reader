//
//  SourceTests.swift
//  PayamTests
//

import XCTest
@testable import Payam

final class SourceTests: XCTestCase {

    // MARK: - Initialization

    func test_init_defaultValues() {
        let source = TestFactory.makeSource()
        XCTAssertTrue(source.isEnabled)
        XCTAssertFalse(source.isPaywalled)
        XCTAssertEqual(source.velocityTier, .article)
        XCTAssertNil(source.decayOverride)
        XCTAssertFalse(source.preferUniqueStories)
        XCTAssertTrue(source.hiddenYouTubeKinds.isEmpty)
    }

    func test_init_emptyWebsiteURL_fallsBackToFeedURL() {
        let source = Source(
            name: "Test",
            feedURL: "https://example.com/feed",
            websiteURL: "",
            categoryID: UUID()
        )
        XCTAssertEqual(source.websiteURL, "https://example.com/feed")
    }

    // MARK: - Effective Velocity Tier

    func test_effectiveVelocityTier_noOverrides_usesInferred() {
        var source = TestFactory.makeSource(velocityTier: .news)
        source.velocityTierOverride = nil
        source.decayOverride = nil
        XCTAssertEqual(source.effectiveVelocityTier, .news)
    }

    func test_effectiveVelocityTier_decayOverride_wins() {
        var source = TestFactory.makeSource(velocityTier: .news)
        source.decayOverride = .essay
        source.velocityTierOverride = .breaking
        XCTAssertEqual(source.effectiveVelocityTier, .essay)
    }

    func test_effectiveVelocityTier_velocityTierOverride_usedWhenNoDecayOverride() {
        var source = TestFactory.makeSource(velocityTier: .news)
        source.decayOverride = nil
        source.velocityTierOverride = .breaking
        XCTAssertEqual(source.effectiveVelocityTier, .breaking)
    }

    // MARK: - Grace Period

    func test_isInGracePeriod_recentlyAdded_true() {
        let source = TestFactory.makeSource(addedAt: Date())
        XCTAssertTrue(source.isInGracePeriod)
    }

    func test_isInGracePeriod_addedOverTwoWeeksAgo_false() {
        let old = Calendar.current.date(byAdding: .day, value: -20, to: Date())!
        let source = TestFactory.makeSource(addedAt: old)
        XCTAssertFalse(source.isInGracePeriod)
    }

    func test_isInGracePeriod_addedExactlyTwoWeeksAgo_false() {
        let exact = Calendar.current.date(byAdding: .day, value: -14, to: Date())!
        let source = TestFactory.makeSource(addedAt: exact)
        XCTAssertFalse(source.isInGracePeriod)
    }
}
