//
//  AppState.swift
//  OpenRSS
//
//  Lightweight global UI state shared between MainTabView and any child
//  view that needs to affect shell-level chrome (tab bar, etc.).
//  Injected into the SwiftUI environment in OpenRSSApp.
//

import Foundation

@Observable
final class AppState {
    /// When true the floating tab bar hides itself (e.g. while reading an article).
    var isReadingArticle: Bool = false

    /// The category ID that was actively selected in TodayView when the user
    /// switched to the Search tab. SearchView reads this on appear to pre-scope
    /// its results. Nil means "All Updates" / no specific folder.
    var activeFolderCategoryID: UUID? = nil

    /// Mirrors UserPreferences.showImages so every ArticleCardView reacts
    /// instantly when the toggle changes in Settings. Initialized from the
    /// persisted value in OpenRSSApp.body via onAppear.
    var showImages: Bool = true
}
