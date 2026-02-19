//
//  MyFeedsViewModel.swift
//  OpenRSS
//
//  ViewModel for the My Feeds tab.
//  Reads folders and feeds from SwiftDataService and provides
//  expansion state, deletion, and navigation to the Add Feed sheet.
//

import Foundation
import SwiftUI

@Observable
final class MyFeedsViewModel {

    // MARK: - Dependencies

    private let dataService: SwiftDataService

    // MARK: - State

    /// Controls presentation of the Add Feed sheet.
    var showingAddFeed: Bool = false

    // MARK: - Computed — Folders & Feeds

    /// All user-created folders, ordered by sortOrder.
    var folders: [Category] {
        dataService.categories.sorted { $0.sortOrder < $1.sortOrder }
    }

    /// Feeds belonging to a given folder.
    func feeds(in folder: Category) -> [Source] {
        dataService.sources.filter { $0.categoryID == folder.id }
    }

    /// Feeds not assigned to any folder.
    var unfiledFeeds: [Source] {
        dataService.sources.filter { $0.categoryID == SwiftDataService.unfiledFolderID }
    }

    /// True when the user has subscribed to at least one feed.
    var hasAnyFeeds: Bool { !dataService.sources.isEmpty }

    // MARK: - Initialization

    init(dataService: SwiftDataService = .shared) {
        self.dataService = dataService
    }

    // MARK: - Search & Unread Counts

    /// Unread article count for a specific folder.
    func unreadCount(for folder: Category) -> Int {
        dataService.unreadCountForCategory(folder.id)
    }

    /// All feeds across every folder + unfiled, filtered by the search text.
    /// Returns all feeds when `text` is blank.
    func filteredAllFeeds(matching text: String) -> [Source] {
        let all = dataService.sources
        let q = text.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return all }
        let lower = q.lowercased()
        return all.filter { $0.name.lowercased().contains(lower) }
    }

    /// Display name of the folder that contains the given source.
    func folderName(for source: Source) -> String {
        if source.categoryID == SwiftDataService.unfiledFolderID { return "Unfiled" }
        return dataService.categories.first { $0.id == source.categoryID }?.name ?? "Unfiled"
    }

    // MARK: - CRUD

    func deleteFolder(_ folder: Category) {
        try? dataService.deleteFolder(id: folder.id)
    }

    func deleteFeed(_ source: Source) {
        try? dataService.deleteFeed(id: source.id)
    }

    func toggleFeedEnabled(_ source: Source) {
        try? dataService.toggleFeedEnabled(id: source.id)
    }
}
