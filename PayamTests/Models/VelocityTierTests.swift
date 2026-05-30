//
//  VelocityTierTests.swift
//  PayamTests
//

import XCTest
@testable import Payam

final class VelocityTierTests: XCTestCase {

    // MARK: - Half-Life Hours

    func test_halfLifeHours_breakingIsShortest() {
        XCTAssertEqual(VelocityTier.breaking.halfLifeHours, 3)
    }

    func test_halfLifeHours_evergreenIsLongest() {
        XCTAssertEqual(VelocityTier.evergreen.halfLifeHours, 720)
    }

    func test_halfLifeHours_ordering() {
        let tiers = VelocityTier.allCases
        for i in 0..<tiers.count - 1 {
            XCTAssertLessThan(tiers[i].halfLifeHours, tiers[i + 1].halfLifeHours,
                "\(tiers[i]) should have shorter half-life than \(tiers[i + 1])")
        }
    }

    // MARK: - Lambda

    func test_lambda_inverslyRelatedToHalfLife() {
        XCTAssertGreaterThan(VelocityTier.breaking.lambda, VelocityTier.news.lambda)
        XCTAssertGreaterThan(VelocityTier.news.lambda, VelocityTier.article.lambda)
    }

    func test_lambda_formula() {
        for tier in VelocityTier.allCases {
            let expected = log(2) / tier.halfLifeHours
            XCTAssertEqual(tier.lambda, expected, accuracy: 1e-10)
        }
    }

    // MARK: - Default Slot Limit

    func test_defaultSlotLimit_breakingIsLowest() {
        XCTAssertEqual(VelocityTier.breaking.defaultSlotLimit, 3)
    }

    func test_defaultSlotLimit_essayIsUnlimited() {
        XCTAssertEqual(VelocityTier.essay.defaultSlotLimit, .max)
    }

    func test_defaultSlotLimit_evergreenIsUnlimited() {
        XCTAssertEqual(VelocityTier.evergreen.defaultSlotLimit, .max)
    }

    func test_defaultSlotLimit_newsIsFive() {
        XCTAssertEqual(VelocityTier.news.defaultSlotLimit, 5)
    }

    // MARK: - Short Description

    func test_shortDescription_allCases() {
        XCTAssertEqual(VelocityTier.breaking.shortDescription, "3h")
        XCTAssertEqual(VelocityTier.news.shortDescription, "18h")
        XCTAssertEqual(VelocityTier.article.shortDescription, "48h")
        XCTAssertEqual(VelocityTier.essay.shortDescription, "7 days")
        XCTAssertEqual(VelocityTier.evergreen.shortDescription, "30 days")
    }

    // MARK: - Display Name

    func test_displayName_allCases() {
        XCTAssertEqual(VelocityTier.breaking.displayName, "Breaking News")
        XCTAssertEqual(VelocityTier.article.displayName, "Articles / Blogs")
        XCTAssertEqual(VelocityTier.evergreen.displayName, "Evergreen / Podcasts")
    }

    // MARK: - Heuristic Assignment

    func test_infer_veryHighFrequency_isBreaking() {
        XCTAssertEqual(VelocityTier.infer(averageItemsPerDay: 25), .breaking)
        XCTAssertEqual(VelocityTier.infer(averageItemsPerDay: 100), .breaking)
    }

    func test_infer_highFrequency_isNews() {
        XCTAssertEqual(VelocityTier.infer(averageItemsPerDay: 10), .news)
        XCTAssertEqual(VelocityTier.infer(averageItemsPerDay: 5), .news)
    }

    func test_infer_mediumFrequency_isArticle() {
        XCTAssertEqual(VelocityTier.infer(averageItemsPerDay: 3), .article)
        XCTAssertEqual(VelocityTier.infer(averageItemsPerDay: 1), .article)
    }

    func test_infer_lowFrequency_isEssay() {
        XCTAssertEqual(VelocityTier.infer(averageItemsPerDay: 0.5), .essay)
        XCTAssertEqual(VelocityTier.infer(averageItemsPerDay: 0.1), .essay)
    }

    func test_infer_veryLowFrequency_isEvergreen() {
        XCTAssertEqual(VelocityTier.infer(averageItemsPerDay: 0.05), .evergreen)
        XCTAssertEqual(VelocityTier.infer(averageItemsPerDay: 0), .evergreen)
    }

    // MARK: - Codable

    func test_codable_roundTrip() throws {
        for tier in VelocityTier.allCases {
            let data = try JSONEncoder().encode(tier)
            let decoded = try JSONDecoder().decode(VelocityTier.self, from: data)
            XCTAssertEqual(decoded, tier)
        }
    }
}
