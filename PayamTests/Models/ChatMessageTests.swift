//
//  ChatMessageTests.swift
//  PayamTests
//

import XCTest
@testable import Payam

final class ChatMessageTests: XCTestCase {

    func test_init_user() {
        let msg = ChatMessage(role: .user, content: "Hello")
        XCTAssertEqual(msg.content, "Hello")
    }

    func test_init_assistant() {
        let msg = ChatMessage(role: .assistant, content: "Hi there")
        XCTAssertEqual(msg.content, "Hi there")
    }

    func test_identifiable_uniqueIDs() {
        let a = ChatMessage(role: .user, content: "A")
        let b = ChatMessage(role: .user, content: "A")
        XCTAssertNotEqual(a.id, b.id)
    }
}
