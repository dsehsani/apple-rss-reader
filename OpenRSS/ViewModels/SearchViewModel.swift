//
//  SearchViewModel.swift
//  OpenRSS
//
//  Manages search query state and delegates article filtering to a
//  pluggable SearchFilter strategy (see SearchFilter.swift).
//
//  ## Swapping search scope at runtime:
//      searchViewModel.mode = .titleAndContent
//  This replaces the active filter strategy in one line.
//  No changes needed in any View or parent ViewModel.
//

import Foundation
import SwiftUI

// MARK: - SearchViewModel

/// Owns the search query string and filtered-results logic.
///
/// The View observes `searchText` for binding and calls
/// `filteredArticles(from:)` to obtain the current result list.
/// The filtering strategy is fully abstracted — the View knows nothing
/// about *how* articles are matched.
@Observable
final class SearchViewModel {

    // MARK: - Public State

    /// The raw text entered by the user. Bind UI directly to this property.
    var searchText: String = ""

    /// The active search mode. Setting this swaps the filter strategy immediately.
    var mode: SearchMode {
        didSet { activeFilter = mode.makeFilter() }
    }

    // MARK: - Private

    /// Concrete filter strategy; updated automatically when `mode` changes.
    private var activeFilter: any SearchFilter

    // MARK: - Initialization

    /// - Parameter mode: Initial search mode. Defaults to `.titleOnly`.
    init(mode: SearchMode = .titleOnly) {
        self.mode = mode
        self.activeFilter = mode.makeFilter()
    }

    // MARK: - Filtering

    /// Returns articles matching the current query using the active filter strategy.
    ///
    /// - Parameter articles: The unfiltered source list.
    /// - Returns: All articles when `searchText` is empty; filtered articles otherwise.
    func filteredArticles(from articles: [Article]) -> [Article] {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return articles }
        return articles.filter { activeFilter.matches(article: $0, query: query.lowercased()) }
    }

    // MARK: - Helpers

    /// Clears the current search query.
    func clear() {
        searchText = ""
    }

    /// `true` when the query contains non-whitespace characters.
    var hasActiveQuery: Bool {
        !searchText.trimmingCharacters(in: .whitespaces).isEmpty
    }
}
