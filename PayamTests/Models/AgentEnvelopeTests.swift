//
//  AgentEnvelopeTests.swift
//  PayamTests
//

import XCTest
@testable import Payam

final class AgentEnvelopeTests: XCTestCase {

    // MARK: - AgentView Decoding

    func test_agentView_text_decodes() throws {
        let json = """
        {
            "type": "text",
            "payload": { "content": "Hello from the agent" }
        }
        """.data(using: .utf8)!

        let view = try JSONDecoder().decode(AgentView.self, from: json)
        if case .text(let payload) = view {
            XCTAssertEqual(payload.content, "Hello from the agent")
        } else {
            XCTFail("Expected .text view")
        }
    }

    func test_agentView_unknown_decodesGracefully() throws {
        let json = """
        {
            "type": "future_widget",
            "payload": { "foo": "bar" }
        }
        """.data(using: .utf8)!

        let view = try JSONDecoder().decode(AgentView.self, from: json)
        if case .unknown(let typeName) = view {
            XCTAssertEqual(typeName, "future_widget")
        } else {
            XCTFail("Expected .unknown view")
        }
    }

    func test_agentView_ruleCard_decodes() throws {
        let json = """
        {
            "type": "rule_card",
            "payload": {
                "displayText": "Hide opinion pieces",
                "predicate": {
                    "keywords": ["opinion"],
                    "phrases": [],
                    "sourceFeedURLs": [],
                    "contentKinds": ["opinion"]
                },
                "scope": "global",
                "rationale": "User asked to hide opinions",
                "sourceText": "hide opinion articles"
            }
        }
        """.data(using: .utf8)!

        let view = try JSONDecoder().decode(AgentView.self, from: json)
        if case .ruleCard(let card) = view {
            XCTAssertEqual(card.displayText, "Hide opinion pieces")
            XCTAssertEqual(card.predicate.keywords, ["opinion"])
            XCTAssertEqual(card.scope, "global")
        } else {
            XCTFail("Expected .ruleCard view")
        }
    }

    func test_agentView_summaryCard_decodes() throws {
        let json = """
        {
            "type": "summary_card",
            "payload": {
                "title": "Article Summary",
                "bullets": ["Point 1", "Point 2"],
                "articleURL": "https://example.com/article"
            }
        }
        """.data(using: .utf8)!

        let view = try JSONDecoder().decode(AgentView.self, from: json)
        if case .summaryCard(let card) = view {
            XCTAssertEqual(card.title, "Article Summary")
            XCTAssertEqual(card.bullets.count, 2)
            XCTAssertEqual(card.articleURL, "https://example.com/article")
        } else {
            XCTFail("Expected .summaryCard view")
        }
    }

    // MARK: - Full Envelope Decoding

    func test_envelope_fullDecode() throws {
        let json = """
        {
            "intent": "discover",
            "view": {
                "type": "text",
                "payload": { "content": "Here are some feeds" }
            },
            "followups": ["What about sports?", "Show me more tech feeds"],
            "usage": {
                "model": "claude-3",
                "inputTokens": 100,
                "cachedInputTokens": 50,
                "outputTokens": 200
            },
            "quota": {
                "remaining": 42,
                "resetAt": "2026-06-01T00:00:00Z"
            }
        }
        """.data(using: .utf8)!

        let envelope = try JSONDecoder().decode(AgentEnvelope.self, from: json)
        XCTAssertEqual(envelope.intent, "discover")
        XCTAssertEqual(envelope.followups.count, 2)
        XCTAssertEqual(envelope.usage?.inputTokens, 100)
        XCTAssertEqual(envelope.quota?.remaining, 42)
    }

    func test_envelope_missingOptionalFields() throws {
        let json = """
        {
            "view": {
                "type": "text",
                "payload": { "content": "Minimal" }
            }
        }
        """.data(using: .utf8)!

        let envelope = try JSONDecoder().decode(AgentEnvelope.self, from: json)
        XCTAssertEqual(envelope.intent, "unknown")
        XCTAssertTrue(envelope.followups.isEmpty)
        XCTAssertNil(envelope.usage)
        XCTAssertNil(envelope.quota)
    }
}
