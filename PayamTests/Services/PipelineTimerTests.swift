//
//  PipelineTimerTests.swift
//  PayamTests
//

import XCTest
@testable import Payam

final class PipelineTimerTests: XCTestCase {

    func test_time_returnsResultAndPositiveDuration() {
        let timer = PipelineTimer()
        let (result, ms) = timer.time("test") {
            42
        }
        XCTAssertEqual(result, 42)
        XCTAssertGreaterThanOrEqual(ms, 0)
    }

    func test_time_throwingWork_propagatesError() {
        let timer = PipelineTimer()
        enum TestError: Error { case boom }

        XCTAssertThrowsError(try timer.time("fail") { throw TestError.boom })
    }

    func test_time_async_returnsResult() async throws {
        let timer = PipelineTimer()
        let (result, ms) = await timer.time("async") {
            "hello"
        }
        XCTAssertEqual(result, "hello")
        XCTAssertGreaterThanOrEqual(ms, 0)
    }
}
