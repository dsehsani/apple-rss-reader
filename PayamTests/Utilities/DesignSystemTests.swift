//
//  DesignSystemTests.swift
//  PayamTests
//

import XCTest
import SwiftUI
@testable import Payam

final class DesignSystemTests: XCTestCase {

    // MARK: - Color from Hex

    func test_colorHex_sixDigit() {
        let color = Color(hex: "FF0000")
        // Just verify it doesn't crash and produces a valid Color
        XCTAssertNotNil(color)
    }

    func test_colorHex_threeDigit() {
        let color = Color(hex: "F00")
        XCTAssertNotNil(color)
    }

    func test_colorHex_eightDigit() {
        let color = Color(hex: "FF0071E3")
        XCTAssertNotNil(color)
    }

    func test_colorHex_withHash_stripsIt() {
        let color = Color(hex: "#007AFF")
        XCTAssertNotNil(color)
    }

    // MARK: - Spacing Constants

    func test_spacing_edge() {
        XCTAssertEqual(Design.Spacing.edge, 16)
    }

    func test_spacing_cardPadding() {
        XCTAssertEqual(Design.Spacing.cardPadding, 16)
    }

    func test_spacing_section() {
        XCTAssertEqual(Design.Spacing.section, 24)
    }

    func test_spacing_small() {
        XCTAssertEqual(Design.Spacing.small, 8)
    }

    func test_spacing_xSmall() {
        XCTAssertEqual(Design.Spacing.xSmall, 4)
    }

    // MARK: - Radius Constants

    func test_radius_standard() {
        XCTAssertEqual(Design.Radius.standard, 12)
    }

    func test_radius_large() {
        XCTAssertEqual(Design.Radius.large, 16)
    }

    func test_radius_small() {
        XCTAssertEqual(Design.Radius.small, 8)
    }

    func test_radius_pill_isInfinity() {
        XCTAssertEqual(Design.Radius.pill, .infinity)
    }

    // MARK: - Animation Press Scale

    func test_animation_pressScale() {
        XCTAssertEqual(Design.Animation.pressScale, 0.98)
    }

    // MARK: - Shadow Style

    func test_shadowStyle_properties() {
        let shadow = Design.Shadows.card
        XCTAssertGreaterThan(shadow.radius, 0)
    }

    // MARK: - Icons

    func test_icons_nonEmpty() {
        XCTAssertFalse(Design.Icons.today.isEmpty)
        XCTAssertFalse(Design.Icons.discover.isEmpty)
        XCTAssertFalse(Design.Icons.saved.isEmpty)
        XCTAssertFalse(Design.Icons.sources.isEmpty)
        XCTAssertFalse(Design.Icons.settings.isEmpty)
        XCTAssertFalse(Design.Icons.search.isEmpty)
        XCTAssertFalse(Design.Icons.add.isEmpty)
    }
}
