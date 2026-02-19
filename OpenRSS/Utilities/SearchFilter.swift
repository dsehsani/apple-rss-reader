//
//  SearchFilter.swift
//  OpenRSS
//
//  Strategy Pattern for pluggable article search criteria.
//
//  ## How to swap from Title-Only to Title+Content:
//  Change the `mode` on your SearchViewModel:
//      searchViewModel.mode = .titleAndContent
//  That's it — no other code changes needed.
//

import Foundation

// MARK: - Search Filter Protocol (Strategy)

/// Defines a single filtering strategy for matching an article against a query.
/// Implement this protocol to add new search criteria (e.g., by category, author, date)
/// without touching the ViewModel or View layers.
protocol SearchFilter {
    /// Returns `true` if `article` is a match for the given lowercased query.
    func matches(article: Article, query: String) -> Bool
}

// MARK: - Fuzzy Match Utility

/// Checks whether `target` is a fuzzy match for `query`.
///
/// Matching strategy (in priority order):
///   1. **Substring**: `target` contains `query` as a contiguous substring — fast, exact.
///   2. **Subsequence**: every character of `query` appears in `target` in order,
///      allowing fragmented / partial input like "rss fd" → "RSS Feed".
///
/// Both comparisons are performed on pre-lowercased strings for case-insensitivity.
func fuzzyMatch(_ target: String, query: String) -> Bool {
    // Fast path — contiguous substring wins immediately.
    if target.contains(query) { return true }

    // Subsequence pass — handles fragmented input and cross-word partial matches.
    var queryIdx = query.startIndex
    for char in target {
        guard queryIdx < query.endIndex else { break }
        if char == query[queryIdx] {
            queryIdx = query.index(after: queryIdx)
        }
    }
    return queryIdx == query.endIndex
}

// MARK: - Concrete Filter Strategies

/// Matches only the article's **title**. This is the default strategy.
///
/// Use this when you want a lightweight, focused search experience.
/// To extend to full-text search, switch to `TitleAndContentFilter`.
struct TitleOnlyFilter: SearchFilter {
    func matches(article: Article, query: String) -> Bool {
        fuzzyMatch(article.title.lowercased(), query: query)
    }
}

/// Matches the article's **title OR excerpt** (body content).
///
/// Activate this strategy to enable full-text search once rich content
/// rendering is added to the app.
struct TitleAndContentFilter: SearchFilter {
    func matches(article: Article, query: String) -> Bool {
        fuzzyMatch(article.title.lowercased(), query: query) ||
        fuzzyMatch(article.excerpt.lowercased(), query: query)
    }
}

// MARK: - Search Mode (Convenience Enum)

/// High-level selector for the active search strategy.
/// Use this to configure `SearchViewModel` without referencing concrete filter types.
///
/// ```swift
/// // Default — title only:
/// let vm = SearchViewModel(mode: .titleOnly)
///
/// // To enable full-text search later:
/// vm.mode = .titleAndContent
/// ```
enum SearchMode {
    /// Search against article titles only (default).
    case titleOnly
    /// Search against article titles and excerpt/body content.
    case titleAndContent

    /// Instantiates the concrete `SearchFilter` for this mode.
    func makeFilter() -> any SearchFilter {
        switch self {
        case .titleOnly:        return TitleOnlyFilter()
        case .titleAndContent:  return TitleAndContentFilter()
        }
    }
}
