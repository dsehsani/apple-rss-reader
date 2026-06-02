//
//  OPMLServiceTests.swift
//  PayamTests
//

import XCTest
@testable import Payam

final class OPMLServiceTests: XCTestCase {

    // MARK: - OPMLImportResult

    func test_importResult_summary_noSkips() {
        let result = OPMLImportResult(imported: 5, skipped: 0)
        XCTAssertEqual(result.summary, "Imported 5 feeds.")
    }

    func test_importResult_summary_withSkips() {
        let result = OPMLImportResult(imported: 3, skipped: 2)
        XCTAssertEqual(result.summary, "Imported 3 feeds, skipped 2 duplicates.")
    }

    func test_importResult_summary_singleFeed() {
        let result = OPMLImportResult(imported: 1, skipped: 0)
        XCTAssertEqual(result.summary, "Imported 1 feed.")
    }

    func test_importResult_summary_singleSkip() {
        let result = OPMLImportResult(imported: 1, skipped: 1)
        XCTAssertEqual(result.summary, "Imported 1 feed, skipped 1 duplicate.")
    }

    func test_importResult_summary_zeroImported() {
        let result = OPMLImportResult(imported: 0, skipped: 5)
        XCTAssertEqual(result.summary, "Imported 0 feeds, skipped 5 duplicates.")
    }

    // MARK: - OPMLError

    func test_opmlError_descriptions() {
        XCTAssertNotNil(OPMLError.unreadableFile.errorDescription)
        XCTAssertNotNil(OPMLError.malformedXML.errorDescription)
        XCTAssertNotNil(OPMLError.noFeedsFound.errorDescription)
    }
}
