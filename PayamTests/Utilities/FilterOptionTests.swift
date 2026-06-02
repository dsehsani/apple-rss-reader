//
//  FilterOptionTests.swift
//  PayamTests
//

import XCTest
@testable import Payam

final class FilterOptionTests: XCTestCase {

    func test_allCases_count() {
        XCTAssertEqual(FilterOption.allCases.count, 3)
    }

    func test_rawValues() {
        XCTAssertEqual(FilterOption.saved.rawValue, "Saved")
        XCTAssertEqual(FilterOption.unread.rawValue, "Unread")
        XCTAssertEqual(FilterOption.today.rawValue, "Today")
    }

    func test_id_equalsRawValue() {
        for option in FilterOption.allCases {
            XCTAssertEqual(option.id, option.rawValue)
        }
    }

    func test_icon_nonEmpty() {
        for option in FilterOption.allCases {
            XCTAssertFalse(option.icon.isEmpty)
        }
    }

    func test_iconColor_nonEmpty() {
        for option in FilterOption.allCases {
            XCTAssertFalse(option.iconColor.isEmpty)
        }
    }

    func test_description_nonEmpty() {
        for option in FilterOption.allCases {
            XCTAssertFalse(option.description.isEmpty)
        }
    }

    func test_hashable_inSet() {
        var set: Set<FilterOption> = []
        set.insert(.saved)
        set.insert(.saved)
        XCTAssertEqual(set.count, 1)

        set.insert(.unread)
        XCTAssertEqual(set.count, 2)
    }
}
