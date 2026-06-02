//
//  AccessibilityIdentifiers.swift
//  PayamUITests
//
//  Centralized constants for accessibility identifiers used in UI tests.
//  Mirror these values in the corresponding SwiftUI source views using
//  .accessibilityIdentifier(AccessibilityID.xxx).
//
//  This file lives in the UI test target so tests reference these constants
//  instead of raw strings. A matching copy should be added to the main app
//  target (or the constants can be defined in a shared framework).
//

import Foundation

/// Namespace for all accessibility identifiers used across the app.
/// Each nested enum corresponds to a screen or feature area.
enum AccessibilityID {

    // MARK: - Tab Bar

    enum Tab {
        static let today    = "tab_today"
        static let discover = "tab_discover"
        static let myFeeds  = "tab_myFeeds"
        static let settings = "tab_settings"
    }

    // MARK: - Today View

    enum Today {
        static let emptyState           = "today_emptyState"
        static let addFirstFeedButton   = "today_addFirstFeedButton"
        static let browseDiscoverButton = "today_browseDiscoverButton"
        static let agentButton          = "today_agentButton"
        static let filterButton         = "today_filterButton"

        /// Dynamic identifier for article cards: "articleCard_<UUID>"
        static func articleCard(id: String) -> String { "articleCard_\(id)" }
    }

    // MARK: - My Feeds View

    enum MyFeeds {
        static let addButton    = "myFeeds_addButton"
        static let searchButton = "myFeeds_searchButton"
        static let searchField  = "myFeeds_searchField"
        static let emptyState   = "myFeeds_emptyState"

        /// Dynamic identifier for folder widgets: "folder_<UUID>"
        static func folder(id: String) -> String { "folder_\(id)" }
    }

    // MARK: - Add Feed View

    enum AddFeed {
        static let urlField        = "addFeed_urlField"
        static let fetchButton     = "addFeed_fetchButton"
        static let nameField       = "addFeed_nameField"
        static let subscribeButton = "addFeed_subscribeButton"
        static let cancelButton    = "addFeed_cancelButton"
    }

    // MARK: - Discover View

    enum Discover {
        static let featuredSection    = "discover_featuredSection"
        static let categoriesSection  = "discover_categoriesSection"
        static let recommendedSection = "discover_recommendedSection"

        static func featuredCard(index: Int) -> String { "discover_featured_\(index)" }
        static func categoryCard(name: String) -> String { "discover_category_\(name)" }
        static func addFeedButton(name: String) -> String { "discover_addFeed_\(name)" }
    }

    // MARK: - Settings View

    enum Settings {
        static let accountButton        = "settings_accountButton"
        static let showImagesToggle     = "settings_showImagesToggle"
        static let openLinksToggle      = "settings_openLinksToggle"
        static let markReadOnScrollToggle = "settings_markReadOnScrollToggle"
        static let clearCacheButton     = "settings_clearCacheButton"
        static let opmlButton           = "settings_opmlButton"
        static let privacyPolicyLink    = "settings_privacyPolicyLink"
        static let readingSignalsLink   = "settings_readingSignalsLink"
    }

    // MARK: - Agent Sheet

    enum Agent {
        static let inputField    = "agent_inputField"
        static let sendButton    = "agent_sendButton"
        static let dismissButton = "agent_dismissButton"
        static let headerTitle   = "agent_headerTitle"
    }

    // MARK: - Article Reader

    enum Reader {
        static let chatButton  = "reader_chatButton"
        static let loading     = "reader_loading"
        static let error       = "reader_error"
        static let safariLink  = "reader_safariLink"
    }

    // MARK: - Onboarding

    enum Onboarding {
        static let continueButton = "onboarding_continueButton"
        static let skipButton     = "onboarding_skipButton"
    }
}
