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
}
