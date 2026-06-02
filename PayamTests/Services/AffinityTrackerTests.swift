//
//  AffinityTrackerTests.swift
//  PayamTests
//

import XCTest
@testable import Payam

final class AffinityTrackerTests: XCTestCase {

    // MARK: - EMA Update (pure function)

    func test_updateAffinity_positiveEvent_raisesScore() {
        let updated = AffinityTracker.updateAffinity(current: 0.0, eventWeight: 1.0)
        XCTAssertGreaterThan(updated, 0.0)
    }

    func test_updateAffinity_negativeEvent_lowersScore() {
        let updated = AffinityTracker.updateAffinity(current: 0.5, eventWeight: -0.5)
        XCTAssertLessThan(updated, 0.5)
    }

    func test_updateAffinity_clampedUpperBound() {
        // Even with very strong positive events, score should not exceed 1.0
        var score = 0.9
        for _ in 0..<100 {
            score = AffinityTracker.updateAffinity(current: score, eventWeight: 1.2)
        }
        XCTAssertLessThanOrEqual(score, 1.0)
    }

    func test_updateAffinity_clampedLowerBound() {
        var score = 0.0
        for _ in 0..<100 {
            score = AffinityTracker.updateAffinity(current: score, eventWeight: -0.5)
        }
        XCTAssertGreaterThanOrEqual(score, -0.3)
    }

    func test_updateAffinity_emaFormula() {
        let alpha = 0.15
        let current = 0.5
        let weight = 1.0
        let expected = alpha * weight + (1.0 - alpha) * current
        let result = AffinityTracker.updateAffinity(current: current, eventWeight: weight)
        XCTAssertEqual(result, expected, accuracy: 0.001)
    }

    func test_updateAffinity_neutralEvent_driftsTowardZero() {
        let current = 0.8
        let updated = AffinityTracker.updateAffinity(current: current, eventWeight: 0.0)
        // EMA with weight 0: score drifts toward 0
        XCTAssertLessThan(updated, current)
        XCTAssertGreaterThan(updated, 0.0)
    }

    func test_updateAffinity_fromZero_smallStep() {
        let updated = AffinityTracker.updateAffinity(current: 0.0, eventWeight: 1.0)
        // alpha * 1.0 + (1-alpha) * 0.0 = 0.15
        XCTAssertEqual(updated, 0.15, accuracy: 0.001)
    }

    func test_updateAffinity_convergesToWeight() {
        // After many identical events, score should converge toward the event weight
        var score = 0.0
        let weight = 0.7
        for _ in 0..<200 {
            score = AffinityTracker.updateAffinity(current: score, eventWeight: weight)
        }
        XCTAssertEqual(score, weight, accuracy: 0.01)
    }
}
