//
//  NudgeCardTests.swift
//  PayamTests
//

import XCTest
@testable import Payam

final class NudgeCardTests: XCTestCase {

    func test_init_defaultMessage() {
        let card = NudgeCard(sourceID: UUID(), sourceName: "TechCrunch", itemCount: 12)
        XCTAssertEqual(card.message, "TechCrunch published 12 items recently")
    }

    func test_init_customMessage() {
        let card = NudgeCard(sourceID: UUID(), sourceName: "Test", itemCount: 5, message: "Custom message")
        XCTAssertEqual(card.message, "Custom message")
    }

    func test_init_emptyMessage_usesDefault() {
        let card = NudgeCard(sourceID: UUID(), sourceName: "Feed", itemCount: 3, message: "")
        XCTAssertEqual(card.message, "Feed published 3 items recently")
    }
}
