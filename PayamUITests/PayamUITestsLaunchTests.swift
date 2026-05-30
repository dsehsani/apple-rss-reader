//
//  PayamUITestsLaunchTests.swift
//  PayamUITests
//
//  Screenshot-based launch tests that run for each UI configuration
//  (light/dark mode, dynamic type sizes, etc.)
//

import XCTest

final class PayamUITestsLaunchTests: XCTestCase {

    override class var runsForEachTargetApplicationUIConfiguration: Bool {
        true
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testLaunch() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-UITesting"]
        app.launch()

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Launch Screen"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
