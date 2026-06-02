//
//  InteractionEventTests.swift
//  PayamTests
//

import XCTest
@testable import Payam

final class InteractionEventTests: XCTestCase {

    // MARK: - Event Type Weights

    func test_weight_strongPositive_sourceBrowseIsHighest() {
        XCTAssertEqual(InteractionEventType.sourceBrowse.weight, 1.2)
    }

    func test_weight_strongPositive_articleOpenIsOne() {
        XCTAssertEqual(InteractionEventType.articleOpen.weight, 1.0)
    }

    func test_weight_mediumPositive_dwellLong() {
        XCTAssertEqual(InteractionEventType.dwellLong.weight, 0.7)
    }

    func test_weight_negative_explicitDismiss() {
        XCTAssertEqual(InteractionEventType.explicitDismiss.weight, -0.5)
    }

    func test_weight_negative_quickBounce() {
        XCTAssertEqual(InteractionEventType.quickBounce.weight, -0.3)
    }

    func test_weight_negative_scrollFastPast_isSmallest() {
        XCTAssertEqual(InteractionEventType.scrollFastPast.weight, -0.1)
    }

    func test_weight_allPositives_greaterThanAllNegatives() {
        let positives: [InteractionEventType] = [
            .articleOpen, .sourceBrowse, .digestExpand, .clusterExpand,
            .articleShare, .dwellLong, .dwellMedium, .scrollSlow, .returnVisit
        ]
        let negatives: [InteractionEventType] = [.quickBounce, .scrollFastPast, .explicitDismiss]

        let minPositive = positives.map(\.weight).min()!
        let maxNegative = negatives.map(\.weight).max()!
        XCTAssertGreaterThan(minPositive, maxNegative)
    }

    // MARK: - Event Initialization

    func test_init_defaults() {
        let event = TestFactory.makeEvent()
        XCTAssertEqual(event.eventType, .articleOpen)
        XCTAssertNil(event.dwellTime)
    }

    func test_init_withDwellTime() {
        let event = TestFactory.makeEvent(eventType: .dwellLong, dwellTime: 30.0)
        XCTAssertEqual(event.eventType, .dwellLong)
        XCTAssertEqual(event.dwellTime, 30.0)
    }
}
