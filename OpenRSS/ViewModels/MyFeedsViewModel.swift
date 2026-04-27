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
@MainActor
final class MyFeedsViewModel {

    // MARK: - Dependencies

    private let dataService: SwiftDataService

    // MARK: - State

    /// Controls presentation of the Add Feed sheet.
    var showingAddFeed: Bool = false

    // MARK: - Folders (stored for reliable @Observable tracking)

    /// All user-created folders, ordered by sortOrder.
    /// Stored (not computed) so that @Observable change notifications fire when
    /// the underlying data changes, triggering immediate UI re-renders.
    private(set) var folders: [Category] = []

    // MARK: - Computed — Feeds

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
        refreshFolders()
        startObservingFolders()
    }

    // MARK: - Private Observation

    /// Synchronously re-reads folders from the data service. Call after any
    /// mutation so the @Observable notification fires immediately, before the
    /// runloop yields.
    private func refreshFolders() {
        folders = dataService.categories.sorted { $0.sortOrder < $1.sortOrder }
    }

    /// Tracks `dataService.categories` for changes that originate outside of
    /// this view model (e.g. CloudKit sync) and keeps `folders` in sync.
    private func startObservingFolders() {
        withObservationTracking {
            _ = dataService.categories
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                self?.refreshFolders()
                self?.startObservingFolders()
            }
        }
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
        refreshFolders()
    }

    func updateFolder(_ folder: Category, name: String? = nil, iconName: String? = nil, colorHex: String? = nil) {
        try? dataService.updateFolder(id: folder.id, name: name, iconName: iconName, colorHex: colorHex)
        refreshFolders()
    }

    func deleteFeed(_ source: Source) {
        try? dataService.deleteFeed(id: source.id)
    }

    func toggleFeedEnabled(_ source: Source) {
        try? dataService.toggleFeedEnabled(id: source.id)
    }

    func togglePaywalled(_ source: Source) {
        try? dataService.toggleFeedPaywalled(id: source.id)
    }
}
