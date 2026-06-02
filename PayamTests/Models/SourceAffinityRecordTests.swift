//
//  SourceAffinityRecordTests.swift
//  PayamTests
//

import XCTest
@testable import Payam

final class SourceAffinityRecordTests: XCTestCase {

    // MARK: - Clamping

    func test_init_clamps_highScore() {
        let record = SourceAffinityRecord(sourceID: UUID(), affinityScore: 5.0)
        XCTAssertEqual(record.affinityScore, 1.0)
    }

    func test_init_clamps_lowScore() {
        let record = SourceAffinityRecord(sourceID: UUID(), affinityScore: -2.0)
        XCTAssertEqual(record.affinityScore, -0.3)
    }

    func test_init_withinRange_notClamped() {
        let record = SourceAffinityRecord(sourceID: UUID(), affinityScore: 0.5)
        XCTAssertEqual(record.affinityScore, 0.5)
    }

    func test_init_boundaryValues() {
        let low = SourceAffinityRecord(sourceID: UUID(), affinityScore: -0.3)
        XCTAssertEqual(low.affinityScore, -0.3)

        let high = SourceAffinityRecord(sourceID: UUID(), affinityScore: 1.0)
        XCTAssertEqual(high.affinityScore, 1.0)
    }

    // MARK: - Affinity Label

    func test_affinityLabel_negative() {
        let record = SourceAffinityRecord(sourceID: UUID(), affinityScore: -0.1)
        XCTAssertEqual(record.affinityLabel, "Low")
    }

    func test_affinityLabel_neutral() {
        let record = SourceAffinityRecord(sourceID: UUID(), affinityScore: 0.15)
        XCTAssertEqual(record.affinityLabel, "Neutral")
    }

    func test_affinityLabel_interested() {
        let record = SourceAffinityRecord(sourceID: UUID(), affinityScore: 0.5)
        XCTAssertEqual(record.affinityLabel, "Interested")
    }

    func test_affinityLabel_highlyInterested() {
        let record = SourceAffinityRecord(sourceID: UUID(), affinityScore: 0.8)
        XCTAssertEqual(record.affinityLabel, "Highly Interested")
    }

    func test_affinityLabel_zero() {
        let record = SourceAffinityRecord(sourceID: UUID(), affinityScore: 0.0)
        XCTAssertEqual(record.affinityLabel, "Neutral")
    }

    // MARK: - Defaults

    func test_init_defaults() {
        let record = SourceAffinityRecord(sourceID: UUID())
        XCTAssertEqual(record.affinityScore, 0.0)
        XCTAssertEqual(record.eventCount, 0)
        XCTAssertEqual(record.velocityTier, .article)
        XCTAssertEqual(record.slotLimit, 8)
    }
}
