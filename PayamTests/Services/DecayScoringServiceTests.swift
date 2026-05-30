//
//  DecayScoringServiceTests.swift
//  PayamTests
//

import XCTest
@testable import Payam

final class DecayScoringServiceTests: XCTestCase {

    // MARK: - Relevance Formula

    func test_relevance_atTimeZero_isOne() {
        let score = DecayScoringService.relevance(hoursSincePublished: 0, tier: .article)
        XCTAssertEqual(score, 1.0, accuracy: 0.001)
    }

    func test_relevance_atHalfLife_isHalf() {
        for tier in VelocityTier.allCases {
            let score = DecayScoringService.relevance(
                hoursSincePublished: tier.halfLifeHours,
                tier: tier
            )
            XCTAssertEqual(score, 0.5, accuracy: 0.01,
                "Relevance at half-life should be ~0.5 for \(tier)")
        }
    }

    func test_relevance_atTwoHalfLives_isQuarter() {
        let tier = VelocityTier.article
        let score = DecayScoringService.relevance(
            hoursSincePublished: tier.halfLifeHours * 2,
            tier: tier
        )
        XCTAssertEqual(score, 0.25, accuracy: 0.02)
    }

    func test_relevance_breakingDecaysFasterThanEvergreen() {
        let hours: Double = 24
        let breakingScore = DecayScoringService.relevance(hoursSincePublished: hours, tier: .breaking)
        let evergreenScore = DecayScoringService.relevance(hoursSincePublished: hours, tier: .evergreen)
        XCTAssertLessThan(breakingScore, evergreenScore)
    }

    // MARK: - Opacity Mapping

    func test_opacity_fullOpacity_aboveThreshold() {
        let opacity = DecayScoringService.opacity(for: 0.85)
        XCTAssertEqual(opacity, 1.0)
    }

    func test_opacity_mediumOpacity_inMiddleRange() {
        let opacity = DecayScoringService.opacity(for: 0.55)
        XCTAssertEqual(opacity, 0.85)
    }

    func test_opacity_lowOpacity_belowMediumThreshold() {
        let opacity = DecayScoringService.opacity(for: 0.25)
        XCTAssertEqual(opacity, 0.7)
    }

    func test_opacity_veryLow_flooredAt07() {
        let opacity = DecayScoringService.opacity(for: 0.1)
        XCTAssertEqual(opacity, 0.7)
    }

    // MARK: - Font Scale

    func test_fontScale_alwaysOne() {
        XCTAssertEqual(DecayScoringService.fontScale(for: 1.0), 1.0)
        XCTAssertEqual(DecayScoringService.fontScale(for: 0.5), 1.0)
        XCTAssertEqual(DecayScoringService.fontScale(for: 0.1), 1.0)
    }

    // MARK: - Thresholds

    func test_thresholds_ordering() {
        XCTAssertGreaterThan(
            DecayScoringService.fullOpacityThreshold,
            DecayScoringService.mediumOpacityThreshold
        )
        XCTAssertGreaterThan(
            DecayScoringService.mediumOpacityThreshold,
            DecayScoringService.lowOpacityThreshold
        )
        XCTAssertEqual(
            DecayScoringService.lowOpacityThreshold,
            DecayScoringService.agedOutThreshold
        )
    }
}
