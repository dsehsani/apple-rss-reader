//
//  FilterOption.swift
//  OpenRSS
//
//  Defines the available filter criteria for the Today feed.
//  Add new cases here and handle them in TodayViewModel.filteredArticles
//  — no other changes needed.
//

import Foundation

// MARK: - FilterOption

/// A discrete filter that can be toggled on/off to narrow the Today article list.
///
/// Each case maps to a single `Article` property so filtering is O(n) and trivial
/// to extend — just add a new case and a corresponding switch arm in the ViewModel.
enum FilterOption: String, CaseIterable, Identifiable, Hashable {

    /// Show only bookmarked/starred articles.
    case saved   = "Saved"

    /// Show only articles the user hasn't opened yet.
    case unread  = "Unread"

    /// Show only articles published on today's calendar date.
    case today   = "Today"

    // MARK: Identifiable

    var id: String { rawValue }

    // MARK: Display

    /// SF Symbol name for this filter's icon in the sheet row.
    var icon: String {
        switch self {
        case .saved:  return "bookmark.fill"
        case .unread: return "circle.inset.filled"
        case .today:  return "sun.max.fill"
        }
    }

    /// Accent color for the icon background chip.
    var iconColor: String {
        switch self {
        case .saved:  return "137cec"   // primary blue — matches bookmarks
        case .unread: return "34c759"   // green — "fresh / new"
        case .today:  return "ff9f0a"   // orange — sunrise / today
        }
    }

    /// One-line description shown beneath each filter row label.
    var description: String {
        switch self {
        case .saved:  return "Only bookmarked articles"
        case .unread: return "Only articles you haven't read"
        case .today:  return "Only articles from today"
        }
    }
}
