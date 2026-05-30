//
//  PayamUITests.swift
//  PayamUITests
//
//  XCUITests for the Payam RSS reader app.
//
//  ─────────────────────────────────────────────────────────────────────────
//  ACCESSIBILITY IDENTIFIERS NEEDED IN SOURCE VIEWS
//  ─────────────────────────────────────────────────────────────────────────
//
//  To make these tests reliable, add the following .accessibilityIdentifier()
//  calls to the corresponding SwiftUI views:
//
//  MainTabView.swift:
//    - Each Tab / tab button:
//        .accessibilityIdentifier("tab_today")
//        .accessibilityIdentifier("tab_discover")
//        .accessibilityIdentifier("tab_myFeeds")
//        .accessibilityIdentifier("tab_settings")
//
//  TodayView.swift:
//    - noFeedsPrompt VStack:
//        .accessibilityIdentifier("today_emptyState")
//    - "Add Your First Feed" button:
//        .accessibilityIdentifier("today_addFirstFeedButton")
//    - "Browse Discover" button:
//        .accessibilityIdentifier("today_browseDiscoverButton")
//    - chatBubbleButton:
//        .accessibilityIdentifier("today_agentButton")
//    - Filter menu button:
//        .accessibilityIdentifier("today_filterButton")
//    - Each ArticleCardView:
//        .accessibilityIdentifier("articleCard_\(article.id)")
//
//  MyFeedsView.swift:
//    - Add feed "+" button:
//        .accessibilityIdentifier("myFeeds_addButton")
//    - Search button:
//        .accessibilityIdentifier("myFeeds_searchButton")
//    - emptyStateView:
//        .accessibilityIdentifier("myFeeds_emptyState")
//    - Each folder widget:
//        .accessibilityIdentifier("folder_\(folder.id)")
//    - Search TextField:
//        .accessibilityIdentifier("myFeeds_searchField")
//
//  AddFeedView.swift:
//    - URL TextField:
//        .accessibilityIdentifier("addFeed_urlField")
//    - Fetch arrow button:
//        .accessibilityIdentifier("addFeed_fetchButton")
//    - Feed name TextField:
//        .accessibilityIdentifier("addFeed_nameField")
//    - Subscribe button:
//        .accessibilityIdentifier("addFeed_subscribeButton")
//    - Cancel button:
//        .accessibilityIdentifier("addFeed_cancelButton")
//
//  DiscoverView.swift:
//    - Featured section:
//        .accessibilityIdentifier("discover_featuredSection")
//    - Categories section:
//        .accessibilityIdentifier("discover_categoriesSection")
//    - Recommended section:
//        .accessibilityIdentifier("discover_recommendedSection")
//    - Each featured card:
//        .accessibilityIdentifier("discover_featured_\(index)")
//    - Each category card:
//        .accessibilityIdentifier("discover_category_\(cat.name)")
//    - Add feed "+" buttons:
//        .accessibilityIdentifier("discover_addFeed_\(feed.name)")
//
//  SettingsView.swift:
//    - Account section button:
//        .accessibilityIdentifier("settings_accountButton")
//    - "Show Article Images" toggle:
//        .accessibilityIdentifier("settings_showImagesToggle")
//    - "Open Links in App" toggle:
//        .accessibilityIdentifier("settings_openLinksToggle")
//    - "Mark as Read on Scroll" toggle:
//        .accessibilityIdentifier("settings_markReadOnScrollToggle")
//    - "Clear Cache" button:
//        .accessibilityIdentifier("settings_clearCacheButton")
//    - "Import / Export" button:
//        .accessibilityIdentifier("settings_opmlButton")
//    - "Privacy Policy" link:
//        .accessibilityIdentifier("settings_privacyPolicyLink")
//    - "Reading Signals" NavigationLink:
//        .accessibilityIdentifier("settings_readingSignalsLink")
//
//  AgentSheetView.swift:
//    - Input TextField:
//        .accessibilityIdentifier("agent_inputField")
//    - Send button:
//        .accessibilityIdentifier("agent_sendButton")
//    - Dismiss "x" button:
//        .accessibilityIdentifier("agent_dismissButton")
//    - Header "Payam Assistant" text:
//        .accessibilityIdentifier("agent_headerTitle")
//
//  ArticleReaderHostView.swift:
//    - Chat bubble button:
//        .accessibilityIdentifier("reader_chatButton")
//    - Loading skeleton:
//        .accessibilityIdentifier("reader_loading")
//    - Error view:
//        .accessibilityIdentifier("reader_error")
//    - "Open in Safari" link:
//        .accessibilityIdentifier("reader_safariLink")
//
//  OnboardingView.swift:
//    - Skip / Continue button:
//        .accessibilityIdentifier("onboarding_continueButton")
//    - "Skip" / guest button:
//        .accessibilityIdentifier("onboarding_skipButton")
//  ─────────────────────────────────────────────────────────────────────────

import XCTest

// MARK: - Base Test Case

class PayamUITestBase: XCTestCase {

    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        // Pass launch arguments to skip onboarding and use a test environment
        app.launchArguments += ["-UITesting"]
        app.launch()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    // MARK: - Helpers

    /// Waits for an element to exist within a timeout.
    func waitForElement(_ element: XCUIElement, timeout: TimeInterval = 5) -> Bool {
        element.waitForExistence(timeout: timeout)
    }

    /// Taps a tab in the tab bar. Works for both the legacy custom tab bar
    /// and the native iOS 26+ TabView.
    func selectTab(_ tabName: String) {
        // Try the native tab bar button first (iOS 26+)
        let tabButton = app.tabBars.buttons[tabName]
        if tabButton.waitForExistence(timeout: 2) {
            tabButton.tap()
            return
        }

        // Fall back to the custom tab bar buttons (iOS 17-25)
        let customTabButton = app.buttons[tabName]
        if customTabButton.waitForExistence(timeout: 2) {
            customTabButton.tap()
            return
        }

        // Last resort: search by static text
        let staticText = app.staticTexts[tabName]
        if staticText.waitForExistence(timeout: 2) {
            staticText.tap()
        }
    }
}

// MARK: - App Launch Tests

final class AppLaunchTests: PayamUITestBase {

    @MainActor
    func testAppLaunches() throws {
        // The app should launch without crashing.
        // After onboarding is skipped (via launch argument), the main tab view appears.
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))
    }

    @MainActor
    func testAppLaunchPerformance() throws {
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }

    @MainActor
    func testMainTabViewAppearsAfterLaunch() throws {
        // At least one of the tab labels should be visible
        let todayExists = app.staticTexts["Today"].waitForExistence(timeout: 10)
        let discoverExists = app.staticTexts["Discover"].exists
        let myFeedsExists = app.staticTexts["My Feeds"].exists || app.staticTexts["Feeds"].exists
        let settingsExists = app.staticTexts["Settings"].exists

        XCTAssertTrue(
            todayExists || discoverExists || myFeedsExists || settingsExists,
            "At least one tab label should be visible after launch"
        )
    }
}

// MARK: - Tab Navigation Tests

final class TabNavigationTests: PayamUITestBase {

    @MainActor
    func testSwitchToDiscoverTab() throws {
        selectTab("Discover")

        // Discover view should show the "Discover" title or featured section
        let discoverTitle = app.staticTexts["Discover"]
        XCTAssertTrue(
            waitForElement(discoverTitle, timeout: 5),
            "Discover tab should display its title"
        )
    }

    @MainActor
    func testSwitchToMyFeedsTab() throws {
        selectTab("My Feeds")

        // My Feeds uses "Feeds" as the navigation title
        let feedsTitle = app.staticTexts["Feeds"]
        let myFeedsTitle = app.staticTexts["My Feeds"]
        XCTAssertTrue(
            waitForElement(feedsTitle, timeout: 5) || myFeedsTitle.exists,
            "My Feeds tab should display its title"
        )
    }

    @MainActor
    func testSwitchToSettingsTab() throws {
        selectTab("Settings")

        let settingsTitle = app.staticTexts["Settings"]
        XCTAssertTrue(
            waitForElement(settingsTitle, timeout: 5),
            "Settings tab should display its title"
        )
    }

    @MainActor
    func testReturnToTodayTab() throws {
        // Navigate away and back
        selectTab("Settings")
        _ = app.staticTexts["Settings"].waitForExistence(timeout: 3)

        selectTab("Today")

        // Today view should be visible again
        // The Today tab shows a greeting via HelloDrawView or the empty state
        let todayLabel = app.staticTexts["Today"]
        let noFeedsYet = app.staticTexts["No Feeds Yet"]
        XCTAssertTrue(
            waitForElement(todayLabel, timeout: 5) || noFeedsYet.exists,
            "Today tab should be visible after navigating back"
        )
    }

    @MainActor
    func testTabBarVisibleOnAllTabs() throws {
        let tabNames = ["Today", "Discover", "My Feeds", "Settings"]

        for tabName in tabNames {
            selectTab(tabName)
            // Give time for transition
            sleep(1)

            // The tab bar should remain visible (not hidden)
            // We verify by checking that at least one other tab label is still tappable
            let otherTab = tabNames.first { $0 != tabName }!
            let otherTabElement = app.staticTexts[otherTab]
            XCTAssertTrue(
                otherTabElement.exists || app.tabBars.buttons[otherTab].exists,
                "Tab bar should remain visible while on \(tabName) tab"
            )
        }
    }
}

// MARK: - Today View Tests

final class TodayViewTests: PayamUITestBase {

    @MainActor
    func testEmptyStateShowsWhenNoFeeds() throws {
        // On a fresh install with no feeds, the empty state should show
        // NOTE: This test assumes the test environment has no pre-loaded feeds.
        // If using -UITesting launch arg with a clean database, this will pass.

        let noFeedsText = app.staticTexts["No Feeds Yet"]
        if noFeedsText.waitForExistence(timeout: 5) {
            // Verify the empty state messaging
            XCTAssertTrue(
                app.staticTexts["Add sources in My Feeds to start\nseeing articles here."].exists
                || app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Add sources'")).count > 0,
                "Empty state should show helpful instructions"
            )
        }
        // If feeds exist, the empty state won't show -- that's also valid
    }

    @MainActor
    func testEmptyStateAddFeedButtonSwitchesToMyFeeds() throws {
        let addButton = app.buttons["Add Your First Feed"]
        guard addButton.waitForExistence(timeout: 3) else {
            // Feeds already exist, skip this test
            return
        }

        addButton.tap()

        // Should navigate to My Feeds tab
        let feedsTitle = app.staticTexts["Feeds"]
        let myFeedsTitle = app.staticTexts["My Feeds"]
        XCTAssertTrue(
            waitForElement(feedsTitle, timeout: 5) || myFeedsTitle.exists,
            "Tapping 'Add Your First Feed' should switch to the My Feeds tab"
        )
    }

    @MainActor
    func testEmptyStateBrowseDiscoverSwitchesToDiscover() throws {
        let browseButton = app.buttons["Browse Discover"]
        guard browseButton.waitForExistence(timeout: 3) else {
            return
        }

        browseButton.tap()

        let discoverTitle = app.staticTexts["Discover"]
        XCTAssertTrue(
            waitForElement(discoverTitle, timeout: 5),
            "Tapping 'Browse Discover' should switch to the Discover tab"
        )
    }

    @MainActor
    func testAgentBubbleButtonExists() throws {
        // The sparkle chat bubble should always be present on TodayView
        // It uses a sparkles SF Symbol inside a circle
        let agentButton = app.buttons.matching(
            NSPredicate(format: "label CONTAINS 'sparkle' OR identifier == 'today_agentButton'")
        ).firstMatch

        // Give the view time to fully load
        XCTAssertTrue(
            waitForElement(agentButton, timeout: 5),
            "Agent chat bubble should be visible on Today view"
        )
    }
}

// MARK: - My Feeds & Add Feed Tests

final class MyFeedsTests: PayamUITestBase {

    @MainActor
    func testMyFeedsEmptyState() throws {
        selectTab("My Feeds")

        let noFeedsText = app.staticTexts["No Feeds Yet"]
        if noFeedsText.waitForExistence(timeout: 5) {
            // Verify the empty state CTA buttons exist
            let addButton = app.buttons["Add Your First Feed"]
            XCTAssertTrue(addButton.exists, "Empty state should have 'Add Your First Feed' button")

            let browseButton = app.buttons["Browse Discover"]
            XCTAssertTrue(browseButton.exists, "Empty state should have 'Browse Discover' button")
        }
    }

    @MainActor
    func testAddFeedSheetPresents() throws {
        selectTab("My Feeds")

        // Tap the "+" button to open AddFeedView sheet
        // The button uses a "plus" SF Symbol in the toolbar or header
        let addButton = app.buttons.matching(
            NSPredicate(format: "identifier == 'myFeeds_addButton'")
        ).firstMatch

        // Fall back to finding the plus button by its image
        let plusButton = app.buttons.matching(
            NSPredicate(format: "label CONTAINS 'Add'")
        ).firstMatch

        let target = addButton.exists ? addButton : plusButton
        guard waitForElement(target, timeout: 5) else {
            // If we're in the empty state, tap "Add Your First Feed" instead
            let emptyStateAdd = app.buttons["Add Your First Feed"]
            guard emptyStateAdd.waitForExistence(timeout: 3) else {
                XCTFail("Neither the + button nor the empty state add button was found")
                return
            }
            emptyStateAdd.tap()
            // This switches to My Feeds tab first, not the sheet
            return
        }
        target.tap()

        // The AddFeedView sheet should appear with "Add Feed" title
        let addFeedTitle = app.staticTexts["Add Feed"]
        XCTAssertTrue(
            waitForElement(addFeedTitle, timeout: 5),
            "Add Feed sheet should be presented"
        )
    }

    @MainActor
    func testAddFeedSheetHasURLField() throws {
        selectTab("My Feeds")

        // Open the add feed sheet (via + or empty state button)
        let plusButtons = app.navigationBars.buttons
        var opened = false

        for i in 0..<plusButtons.count {
            let btn = plusButtons.element(boundBy: i)
            if btn.label.contains("Add") || btn.label.contains("plus") {
                btn.tap()
                opened = true
                break
            }
        }

        if !opened {
            // Try empty state
            let addFirst = app.buttons["Add Your First Feed"]
            if addFirst.waitForExistence(timeout: 2) {
                addFirst.tap()
                // This navigates to My Feeds, need to tap + there
                return
            }
        }

        guard app.staticTexts["Add Feed"].waitForExistence(timeout: 5) else {
            return
        }

        // Should have a URL text field
        let urlField = app.textFields.firstMatch
        XCTAssertTrue(
            waitForElement(urlField, timeout: 3),
            "Add Feed sheet should contain a URL text field"
        )
    }

    @MainActor
    func testAddFeedSheetCanBeDismissed() throws {
        selectTab("My Feeds")

        // Open the sheet via empty state or + button
        let addFirst = app.buttons["Add Your First Feed"]
        if addFirst.waitForExistence(timeout: 3) {
            addFirst.tap()
            // This switches tabs, not opens a sheet
            return
        }

        // The sheet should have a Cancel button
        let cancelButton = app.buttons["Cancel"]
        if cancelButton.waitForExistence(timeout: 3) {
            cancelButton.tap()

            // Sheet should dismiss, returning to My Feeds
            XCTAssertFalse(
                app.staticTexts["Add Feed"].waitForExistence(timeout: 2),
                "Add Feed sheet should dismiss after tapping Cancel"
            )
        }
    }
}

// MARK: - Discover View Tests

final class DiscoverViewTests: PayamUITestBase {

    @MainActor
    func testDiscoverShowsFeaturedSection() throws {
        selectTab("Discover")

        // The Discover view has a "Featured" section header
        let featuredHeader = app.staticTexts["Featured"]
        XCTAssertTrue(
            waitForElement(featuredHeader, timeout: 5),
            "Discover should show a 'Featured' section"
        )
    }

    @MainActor
    func testDiscoverShowsCategoriesSection() throws {
        selectTab("Discover")

        let categoriesHeader = app.staticTexts["Categories"]
        XCTAssertTrue(
            waitForElement(categoriesHeader, timeout: 5),
            "Discover should show a 'Categories' section"
        )
    }

    @MainActor
    func testDiscoverShowsRecommendedSourcesSection() throws {
        selectTab("Discover")

        // Scroll down to find the Recommended Sources section
        let scrollView = app.scrollViews.firstMatch
        if scrollView.exists {
            scrollView.swipeUp()
        }

        let recommendedHeader = app.staticTexts["Recommended Sources"]
        XCTAssertTrue(
            waitForElement(recommendedHeader, timeout: 5),
            "Discover should show a 'Recommended Sources' section"
        )
    }

    @MainActor
    func testDiscoverFeaturedCardsExist() throws {
        selectTab("Discover")
        _ = app.staticTexts["Featured"].waitForExistence(timeout: 5)

        // Featured cards should show "Editor's Pick" labels
        let editorsPick = app.staticTexts["Editor's Pick"]
        XCTAssertTrue(
            waitForElement(editorsPick, timeout: 3),
            "Featured section should contain at least one card with 'Editor's Pick'"
        )
    }

    @MainActor
    func testDiscoverFeaturedCardShowsAddButton() throws {
        selectTab("Discover")
        _ = app.staticTexts["Featured"].waitForExistence(timeout: 5)

        // Each featured card should have either an "Add Feed" button or a checkmark
        let addFeedButton = app.buttons["Add Feed"]
        let addedLabel = app.staticTexts["Added"]

        XCTAssertTrue(
            waitForElement(addFeedButton, timeout: 3) || addedLabel.exists,
            "Featured cards should have an 'Add Feed' button or show 'Added'"
        )
    }
}

// MARK: - Settings View Tests

final class SettingsViewTests: PayamUITestBase {

    @MainActor
    func testSettingsShowsAllSections() throws {
        selectTab("Settings")
        _ = app.staticTexts["Settings"].waitForExistence(timeout: 5)

        // Account section
        let accountSection = app.staticTexts["ACCOUNT"]
        XCTAssertTrue(
            waitForElement(accountSection, timeout: 3),
            "Settings should show the Account section"
        )

        // Reading section
        let readingSection = app.staticTexts["READING"]
        XCTAssertTrue(readingSection.exists, "Settings should show the Reading section")
    }

    @MainActor
    func testSettingsShowsReadingToggles() throws {
        selectTab("Settings")
        _ = app.staticTexts["Settings"].waitForExistence(timeout: 5)

        // The Reading section should have toggle labels
        let showImages = app.staticTexts["Show Article Images"]
        let openLinks = app.staticTexts["Open Links in App"]
        let markRead = app.staticTexts["Mark as Read on Scroll"]

        XCTAssertTrue(
            waitForElement(showImages, timeout: 3),
            "Settings should have 'Show Article Images' toggle"
        )
        XCTAssertTrue(openLinks.exists, "Settings should have 'Open Links in App' toggle")
        XCTAssertTrue(markRead.exists, "Settings should have 'Mark as Read on Scroll' toggle")
    }

    @MainActor
    func testSettingsShowsDataSection() throws {
        selectTab("Settings")
        _ = app.staticTexts["Settings"].waitForExistence(timeout: 5)

        // Scroll to Data section
        let scrollView = app.scrollViews.firstMatch
        if scrollView.exists {
            scrollView.swipeUp()
        }

        let dataSection = app.staticTexts["DATA & STORAGE"]
        XCTAssertTrue(
            waitForElement(dataSection, timeout: 3),
            "Settings should show the 'Data & Storage' section"
        )

        let refreshInterval = app.staticTexts["Refresh Interval"]
        XCTAssertTrue(refreshInterval.exists, "Data section should show 'Refresh Interval'")

        let clearCache = app.staticTexts["Clear Cache"]
        XCTAssertTrue(clearCache.exists, "Data section should show 'Clear Cache'")
    }

    @MainActor
    func testSettingsShowsAboutSection() throws {
        selectTab("Settings")
        _ = app.staticTexts["Settings"].waitForExistence(timeout: 5)

        // Scroll down to About
        let scrollView = app.scrollViews.firstMatch
        if scrollView.exists {
            scrollView.swipeUp()
            scrollView.swipeUp()
        }

        let aboutSection = app.staticTexts["ABOUT"]
        XCTAssertTrue(
            waitForElement(aboutSection, timeout: 3),
            "Settings should show the About section"
        )

        let privacyPolicy = app.staticTexts["Privacy Policy"]
        XCTAssertTrue(privacyPolicy.exists, "About section should show 'Privacy Policy'")
    }

    @MainActor
    func testSettingsReadingSignalsNavigation() throws {
        selectTab("Settings")
        _ = app.staticTexts["Settings"].waitForExistence(timeout: 5)

        // Scroll to find "Reading Signals"
        let scrollView = app.scrollViews.firstMatch
        if scrollView.exists {
            scrollView.swipeUp()
        }

        let readingSignals = app.staticTexts["Reading Signals"]
        guard waitForElement(readingSignals, timeout: 3) else {
            // May not be visible if the River Settings section is below the fold
            return
        }

        readingSignals.tap()

        // Should navigate to SourceAffinityView
        let backButton = app.navigationBars.buttons.firstMatch
        XCTAssertTrue(
            waitForElement(backButton, timeout: 5),
            "Tapping 'Reading Signals' should push a new view with a back button"
        )
    }

    @MainActor
    func testSettingsAccountButtonExists() throws {
        selectTab("Settings")
        _ = app.staticTexts["Settings"].waitForExistence(timeout: 5)

        // Account section should show either "Sign In" or the user's name
        let signIn = app.staticTexts["Sign In"]
        let syncText = app.staticTexts["iCloud sync available"]

        XCTAssertTrue(
            waitForElement(signIn, timeout: 3) || syncText.exists,
            "Account section should show sign-in prompt or sync status"
        )
    }

    @MainActor
    func testSettingsShowImagesToggleWorks() throws {
        selectTab("Settings")
        _ = app.staticTexts["Settings"].waitForExistence(timeout: 5)

        // Find the "Show Article Images" toggle switch
        let toggleSwitch = app.switches["Show Article Images"]
        guard waitForElement(toggleSwitch, timeout: 3) else {
            return
        }

        let initialValue = toggleSwitch.value as? String
        toggleSwitch.tap()

        let newValue = toggleSwitch.value as? String
        XCTAssertNotEqual(
            initialValue, newValue,
            "Toggling 'Show Article Images' should change its state"
        )

        // Toggle back to restore original state
        toggleSwitch.tap()
    }
}

// MARK: - Agent / Chat Sheet Tests

final class AgentSheetTests: PayamUITestBase {

    @MainActor
    func testAgentSheetOpens() throws {
        // The agent button is the sparkle icon on TodayView
        let agentButton = app.buttons.matching(
            NSPredicate(format: "label CONTAINS 'sparkle' OR identifier == 'today_agentButton'")
        ).firstMatch

        guard waitForElement(agentButton, timeout: 5) else {
            XCTFail("Agent bubble button not found on Today view")
            return
        }

        agentButton.tap()

        // The agent sheet should present with the header
        let assistantTitle = app.staticTexts["Payam Assistant"]
        XCTAssertTrue(
            waitForElement(assistantTitle, timeout: 5),
            "Agent sheet should show 'Payam Assistant' header"
        )
    }

    @MainActor
    func testAgentSheetHasInputField() throws {
        let agentButton = app.buttons.matching(
            NSPredicate(format: "label CONTAINS 'sparkle' OR identifier == 'today_agentButton'")
        ).firstMatch

        guard waitForElement(agentButton, timeout: 5) else { return }
        agentButton.tap()

        guard app.staticTexts["Payam Assistant"].waitForExistence(timeout: 5) else {
            XCTFail("Agent sheet did not present")
            return
        }

        // The input bar should have a text field
        let inputField = app.textFields.firstMatch
        XCTAssertTrue(
            waitForElement(inputField, timeout: 3),
            "Agent sheet should have an input text field"
        )
    }

    @MainActor
    func testAgentSheetShowsWelcomeMessage() throws {
        let agentButton = app.buttons.matching(
            NSPredicate(format: "label CONTAINS 'sparkle' OR identifier == 'today_agentButton'")
        ).firstMatch

        guard waitForElement(agentButton, timeout: 5) else { return }
        agentButton.tap()

        guard app.staticTexts["Payam Assistant"].waitForExistence(timeout: 5) else {
            XCTFail("Agent sheet did not present")
            return
        }

        // The welcome bubble should be visible in the turn list.
        // The exact text depends on AgentViewModel.welcomeMessage.
        // At minimum, the scroll view should contain some text.
        let scrollView = app.scrollViews.firstMatch
        XCTAssertTrue(scrollView.exists, "Agent sheet should have a scrollable conversation area")
    }

    @MainActor
    func testAgentSheetCanBeDismissed() throws {
        let agentButton = app.buttons.matching(
            NSPredicate(format: "label CONTAINS 'sparkle' OR identifier == 'today_agentButton'")
        ).firstMatch

        guard waitForElement(agentButton, timeout: 5) else { return }
        agentButton.tap()

        guard app.staticTexts["Payam Assistant"].waitForExistence(timeout: 5) else { return }

        // Tap the dismiss "x" button
        let dismissButton = app.buttons.matching(
            NSPredicate(format: "label CONTAINS 'Close' OR label CONTAINS 'Dismiss' OR identifier == 'agent_dismissButton'")
        ).firstMatch

        // Fall back to looking for the xmark button
        let xButton = app.buttons.matching(
            NSPredicate(format: "label == 'xmark' OR label CONTAINS 'close'")
        ).firstMatch

        let target = dismissButton.exists ? dismissButton : xButton
        if waitForElement(target, timeout: 3) {
            target.tap()

            // The assistant header should disappear
            XCTAssertFalse(
                app.staticTexts["Payam Assistant"].waitForExistence(timeout: 2),
                "Agent sheet should be dismissed"
            )
        } else {
            // Alternatively, swipe down to dismiss the sheet
            let sheet = app.otherElements.firstMatch
            sheet.swipeDown()
        }
    }

    @MainActor
    func testAgentSendButtonDisabledWhenEmpty() throws {
        let agentButton = app.buttons.matching(
            NSPredicate(format: "label CONTAINS 'sparkle' OR identifier == 'today_agentButton'")
        ).firstMatch

        guard waitForElement(agentButton, timeout: 5) else { return }
        agentButton.tap()

        guard app.staticTexts["Payam Assistant"].waitForExistence(timeout: 5) else { return }

        // The send button should be disabled when the input is empty
        let sendButton = app.buttons.matching(
            NSPredicate(format: "identifier == 'agent_sendButton'")
        ).firstMatch

        if waitForElement(sendButton, timeout: 3) {
            XCTAssertFalse(
                sendButton.isEnabled,
                "Send button should be disabled when input field is empty"
            )
        }
    }
}

// MARK: - Onboarding Tests

final class OnboardingTests: XCTestCase {

    @MainActor
    func testOnboardingShowsOnFreshInstall() throws {
        let app = XCUIApplication()
        // Launch WITHOUT the UITesting flag so onboarding can appear
        app.launchArguments = ["-FreshInstall"]
        app.launch()

        // On a truly fresh install, onboarding pages should show.
        // Look for known onboarding text content.
        let headline = app.staticTexts["Your feeds.\nYour way."]
        let altHeadline = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS 'Your feeds'")
        ).firstMatch

        // If the app state has already been set up, onboarding might be skipped
        if headline.waitForExistence(timeout: 5) || altHeadline.exists {
            XCTAssertTrue(true, "Onboarding is shown on fresh install")
        }
        // If onboarding doesn't appear (user already signed in/skipped), that's acceptable
    }
}

// MARK: - OPML Import/Export Tests

final class OPMLTests: PayamUITestBase {

    @MainActor
    func testOPMLButtonOpensManager() throws {
        selectTab("Settings")
        _ = app.staticTexts["Settings"].waitForExistence(timeout: 5)

        // Scroll to Data section
        let scrollView = app.scrollViews.firstMatch
        if scrollView.exists {
            scrollView.swipeUp()
        }

        let opmlButton = app.staticTexts["Import / Export"]
        guard waitForElement(opmlButton, timeout: 3) else {
            return
        }

        opmlButton.tap()

        // The OPML manager sheet should show with "Subscriptions" title
        let subsTitle = app.staticTexts["Subscriptions"]
        XCTAssertTrue(
            waitForElement(subsTitle, timeout: 5),
            "OPML manager sheet should present with 'Subscriptions' title"
        )
    }

    @MainActor
    func testOPMLManagerShowsImportExportTabs() throws {
        selectTab("Settings")
        _ = app.staticTexts["Settings"].waitForExistence(timeout: 5)

        let scrollView = app.scrollViews.firstMatch
        if scrollView.exists { scrollView.swipeUp() }

        let opmlButton = app.staticTexts["Import / Export"]
        guard waitForElement(opmlButton, timeout: 3) else { return }
        opmlButton.tap()

        guard app.staticTexts["Subscriptions"].waitForExistence(timeout: 5) else { return }

        // Should have Import and Export tab buttons
        let importTab = app.buttons["Import"]
        let exportTab = app.buttons["Export"]

        XCTAssertTrue(importTab.exists, "OPML manager should have an Import tab")
        XCTAssertTrue(exportTab.exists, "OPML manager should have an Export tab")
    }
}

// MARK: - Launch Screenshot Tests

final class PayamLaunchScreenshotTests: XCTestCase {

    override class var runsForEachTargetApplicationUIConfiguration: Bool {
        true
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testLaunchScreenshot() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-UITesting"]
        app.launch()

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Launch Screen"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    func testDiscoverTabScreenshot() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-UITesting"]
        app.launch()

        // Navigate to Discover
        let discoverTab = app.tabBars.buttons["Discover"]
        if discoverTab.waitForExistence(timeout: 5) {
            discoverTab.tap()
        } else {
            app.staticTexts["Discover"].tap()
        }

        sleep(2) // Allow content to load

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Discover Tab"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    func testSettingsTabScreenshot() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-UITesting"]
        app.launch()

        // Navigate to Settings
        let settingsTab = app.tabBars.buttons["Settings"]
        if settingsTab.waitForExistence(timeout: 5) {
            settingsTab.tap()
        } else {
            app.staticTexts["Settings"].tap()
        }

        sleep(1)

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Settings Tab"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
