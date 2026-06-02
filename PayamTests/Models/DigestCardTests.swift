//
//  DigestCardTests.swift
//  PayamTests
//

import XCTest
@testable import Payam

final class DigestCardTests: XCTestCase {

    func test_id_isDeterministic() {
        let sourceID = UUID()
        let date = Date()

        let card1 = DigestCard(
            sourceID: sourceID,
            sourceName: "Test",
            itemCount: 3,
            highlights: ["A"],
            overflowIDs: [UUID()],
            insertionPosition: date
        )
        let card2 = DigestCard(
            sourceID: sourceID,
            sourceName: "Different Name",
            itemCount: 5,
            highlights: ["B", "C"],
            overflowIDs: [UUID()],
            insertionPosition: date
        )

        // Same sourceID + same day should produce the same computed ID
        XCTAssertEqual(card1.id, card2.id)
    }

    func test_id_differentDays_differentIDs() {
        let sourceID = UUID()
        let today = Date()
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: today)!

        let card1 = DigestCard(
            sourceID: sourceID,
            sourceName: "Test",
            itemCount: 3,
            highlights: [],
            overflowIDs: [],
            insertionPosition: today
        )
        let card2 = DigestCard(
            sourceID: sourceID,
            sourceName: "Test",
            itemCount: 3,
            highlights: [],
            overflowIDs: [],
            insertionPosition: tomorrow
        )

        XCTAssertNotEqual(card1.id, card2.id)
    }

    func test_id_differentSources_differentIDs() {
        let date = Date()
        let card1 = DigestCard(
            sourceID: UUID(),
            sourceName: "A",
            itemCount: 1,
            highlights: [],
            overflowIDs: [],
            insertionPosition: date
        )
        let card2 = DigestCard(
            sourceID: UUID(),
            sourceName: "B",
            itemCount: 1,
            highlights: [],
            overflowIDs: [],
            insertionPosition: date
        )

        XCTAssertNotEqual(card1.id, card2.id)
    }

    func test_init_storesAllFields() {
        let sourceID = UUID()
        let overflow = [UUID(), UUID()]
        let card = DigestCard(
            sourceID: sourceID,
            sourceName: "News Wire",
            itemCount: 8,
            highlights: ["Story 1", "Story 2", "Story 3"],
            overflowIDs: overflow,
            insertionPosition: Date()
        )

        XCTAssertEqual(card.sourceID, sourceID)
        XCTAssertEqual(card.sourceName, "News Wire")
        XCTAssertEqual(card.itemCount, 8)
        XCTAssertEqual(card.highlights.count, 3)
        XCTAssertEqual(card.overflowIDs, overflow)
    }
}
