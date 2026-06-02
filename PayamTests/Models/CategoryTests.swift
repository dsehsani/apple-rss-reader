//
//  CategoryTests.swift
//  PayamTests
//

import XCTest
@testable import Payam

final class CategoryTests: XCTestCase {

    func test_init_defaults() {
        let cat = Category(name: "Tech")
        XCTAssertEqual(cat.name, "Tech")
        XCTAssertEqual(cat.icon, "folder.fill")
        XCTAssertEqual(cat.sortOrder, 0)
    }

    func test_allUpdates_hasFixedID() {
        let allUpdates = Category.allUpdates
        XCTAssertEqual(allUpdates.id, UUID(uuidString: "00000000-0000-0000-0000-000000000001"))
        XCTAssertEqual(allUpdates.name, "All Updates")
        XCTAssertEqual(allUpdates.sortOrder, -1)
    }

    func test_equatable_sameName_sameID() {
        let a = Category(id: UUID(), name: "Tech", icon: "cpu", sortOrder: 0)
        let b = Category(id: a.id, name: "Tech", icon: "cpu", sortOrder: 0)
        XCTAssertEqual(a, b)
    }

    func test_equatable_differentIcon_notEqual() {
        let id = UUID()
        let a = Category(id: id, name: "Tech", icon: "cpu", sortOrder: 0)
        let b = Category(id: id, name: "Tech", icon: "globe", sortOrder: 0)
        XCTAssertNotEqual(a, b)
    }

    func test_hashable_sameValues_sameHash() {
        let id = UUID()
        let a = Category(id: id, name: "A", icon: "star", sortOrder: 1)
        let b = Category(id: id, name: "A", icon: "star", sortOrder: 1)
        XCTAssertEqual(a.hashValue, b.hashValue)
    }
}
