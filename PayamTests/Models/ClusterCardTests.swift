//
//  ClusterCardTests.swift
//  PayamTests
//

import XCTest
@testable import Payam

final class ClusterCardTests: XCTestCase {

    func test_init_storesFields() {
        let canonical = TestFactory.makeFeedItem(title: "Canonical")
        let card = ClusterCard(
            canonicalItem: canonical,
            sourceCount: 3,
            sourceNames: ["A", "B", "C"],
            allItemIDs: [UUID(), UUID(), UUID()]
        )

        XCTAssertEqual(card.canonicalItem.title, "Canonical")
        XCTAssertEqual(card.sourceCount, 3)
        XCTAssertEqual(card.sourceNames, ["A", "B", "C"])
        XCTAssertEqual(card.allItemIDs.count, 3)
        XCTAssertTrue(card.allItems.isEmpty, "allItems defaults to empty")
    }

    func test_init_withAllItems() {
        let items = (0..<3).map { _ in TestFactory.makeFeedItem() }
        let card = ClusterCard(
            canonicalItem: items[0],
            sourceCount: 2,
            sourceNames: ["X", "Y"],
            allItemIDs: items.map(\.id),
            allItems: items
        )

        XCTAssertEqual(card.allItems.count, 3)
    }
}
