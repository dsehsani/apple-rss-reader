//
//  RiverItemTests.swift
//  PayamTests
//

import XCTest
@testable import Payam

final class RiverItemTests: XCTestCase {

    // MARK: - ID

    func test_id_article_returnsFeedItemID() {
        let item = TestFactory.makeFeedItem()
        let riverItem = RiverItem.article(item)
        XCTAssertEqual(riverItem.id, item.id)
    }

    func test_id_cluster_returnsClusterCardID() {
        let card = ClusterCard(
            canonicalItem: TestFactory.makeFeedItem(),
            sourceCount: 2,
            sourceNames: ["A", "B"],
            allItemIDs: [UUID(), UUID()]
        )
        let riverItem = RiverItem.cluster(card)
        XCTAssertEqual(riverItem.id, card.id)
    }

    func test_id_nudge_returnsNudgeID() {
        let nudge = NudgeCard(sourceID: UUID(), sourceName: "Test", itemCount: 5)
        let riverItem = RiverItem.nudge(nudge)
        XCTAssertEqual(riverItem.id, nudge.id)
    }

    // MARK: - Positional Weight

    func test_positionalWeight_article_equalsRelevanceScore() {
        let item = TestFactory.makeFeedItem(relevanceScore: 0.75)
        let riverItem = RiverItem.article(item)
        XCTAssertEqual(riverItem.positionalWeight, 0.75)
    }

    func test_positionalWeight_cluster_boostedByTenPercent() {
        let item = TestFactory.makeFeedItem(relevanceScore: 0.8)
        let card = ClusterCard(
            canonicalItem: item,
            sourceCount: 2,
            sourceNames: ["A", "B"],
            allItemIDs: [UUID()]
        )
        let riverItem = RiverItem.cluster(card)
        XCTAssertEqual(riverItem.positionalWeight, 0.8 * 1.1, accuracy: 0.001)
    }

    func test_positionalWeight_nudge_isNearTop() {
        let nudge = NudgeCard(sourceID: UUID(), sourceName: "Test", itemCount: 3)
        let riverItem = RiverItem.nudge(nudge)
        XCTAssertEqual(riverItem.positionalWeight, 0.95)
    }

    // MARK: - Relevance Score

    func test_relevanceScore_article_matchesFeedItem() {
        let item = TestFactory.makeFeedItem(relevanceScore: 0.42)
        let riverItem = RiverItem.article(item)
        XCTAssertEqual(riverItem.relevanceScore, 0.42)
    }

    func test_relevanceScore_nudge_isOne() {
        let nudge = NudgeCard(sourceID: UUID(), sourceName: "Test", itemCount: 3)
        let riverItem = RiverItem.nudge(nudge)
        XCTAssertEqual(riverItem.relevanceScore, 1.0)
    }

    func test_relevanceScore_digest_isPointEight() {
        let digest = DigestCard(
            sourceID: UUID(),
            sourceName: "Test",
            itemCount: 3,
            highlights: ["A"],
            overflowIDs: [UUID()],
            insertionPosition: Date()
        )
        let riverItem = RiverItem.digest(digest)
        XCTAssertEqual(riverItem.relevanceScore, 0.8)
    }

    // MARK: - Adjusted Positional Weight

    func test_adjustedPositionalWeight_preferUnique_deboosted() {
        let sourceID = UUID()
        let items = [TestFactory.makeFeedItem(sourceID: sourceID)]
        let card = ClusterCard(
            canonicalItem: items[0],
            sourceCount: 1,
            sourceNames: ["Source"],
            allItemIDs: items.map(\.id),
            allItems: items + [TestFactory.makeFeedItem(sourceID: sourceID)]
        )
        let riverItem = RiverItem.cluster(card)

        let prefMap: [UUID: Bool] = [sourceID: true]
        let weight = riverItem.adjustedPositionalWeight(preferUniqueStories: prefMap)

        // With preferUnique, the weight should use Article.riverScore which deboosted
        XCTAssertLessThan(weight, card.canonicalItem.relevanceScore * 1.1)
    }

    func test_adjustedPositionalWeight_noPreference_boosted() {
        let sourceID = UUID()
        let item = TestFactory.makeFeedItem(sourceID: sourceID, relevanceScore: 0.8)
        let card = ClusterCard(
            canonicalItem: item,
            sourceCount: 1,
            sourceNames: ["Source"],
            allItemIDs: [item.id]
        )
        let riverItem = RiverItem.cluster(card)

        let prefMap: [UUID: Bool] = [sourceID: false]
        let weight = riverItem.adjustedPositionalWeight(preferUniqueStories: prefMap)
        XCTAssertEqual(weight, 0.8 * 1.1, accuracy: 0.001)
    }

    // MARK: - RiverSnapshot

    func test_riverSnapshot_initDefaults() {
        let snapshot = RiverSnapshot(items: [])
        XCTAssertTrue(snapshot.items.isEmpty)
        XCTAssertEqual(snapshot.pipelineDurationMs, 0)
    }

    func test_riverSnapshot_customDuration() {
        let snapshot = RiverSnapshot(items: [], pipelineDurationMs: 42.5)
        XCTAssertEqual(snapshot.pipelineDurationMs, 42.5)
    }
}
