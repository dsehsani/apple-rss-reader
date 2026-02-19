//
//  AddFeedViewModel.swift
//  OpenRSS
//
//  Drives the Add Feed sheet:
//    1. User enters a URL
//    2. Feed title is auto-fetched from the RSS channel metadata
//    3. User picks or creates a folder
//    4. Tapping Subscribe persists to SwiftData via SwiftDataService
//

import Foundation
import SwiftUI
import FeedKit

@Observable
@MainActor
final class AddFeedViewModel {

    // MARK: - Input State

    /// Raw URL text typed by the user.
    var urlText: String = ""

    /// UUID of the selected folder. `nil` = unfiled.
    var selectedFolderID: UUID? = nil

    /// Name for a new folder being created inline.
    var newFolderName: String = ""

    /// SF Symbol name for the new folder's icon.
    var newFolderIcon: String = "folder.fill"

    /// Hex color (no #) for the new folder's tint color.
    var newFolderColorHex: String = "007AFF"

    /// Whether the user has chosen to create a new folder.
    var isCreatingNewFolder: Bool = false

    // MARK: - Fetch State

    /// The channel title auto-fetched from the feed (editable by user).
    var fetchedTitle: String = ""

    var isFetching: Bool = false
    var fetchError: String? = nil
    var hasFetchedSuccessfully: Bool = false

    // MARK: - Save State

    var isSaving: Bool = false
    var saveError: String? = nil

    // MARK: - Computed

    /// The title to save — falls back to the URL host if fetch returned nothing.
    var displayTitle: String {
        fetchedTitle.isEmpty ? (URL(string: normalizedURL)?.host ?? urlText) : fetchedTitle
    }

    /// Available existing folders for the picker.
    var availableFolders: [Category] {
        SwiftDataService.shared.categories
    }

    /// Subscribe button is enabled once a fetch succeeded and we're not busy.
    var canSubscribe: Bool {
        !urlText.trimmingCharacters(in: .whitespaces).isEmpty &&
        hasFetchedSuccessfully &&
        !isSaving
    }

    // MARK: - Private

    private let rssService = RSSService()

    /// URL with `https://` prepended if the user omitted the scheme.
    private var normalizedURL: String {
        let raw = urlText.trimmingCharacters(in: .whitespaces)
        return raw.hasPrefix("http") ? raw : "https://\(raw)"
    }

    // MARK: - Actions

    /// Fetches the RSS channel title from the entered URL.
    /// Uses FeedKit directly on the raw data so we get the channel/feed name,
    /// not just article titles.
    func fetchFeedTitle() async {
        let urlString = normalizedURL
        guard let url = URL(string: urlString) else {
            fetchError = "Please enter a valid URL."
            return
        }

        isFetching = true
        fetchError = nil
        hasFetchedSuccessfully = false
        fetchedTitle = ""

        do {
            let data = try await rssService.fetchFeedData(from: url)

            // Parse channel metadata with FeedKit to extract the feed title
            let title: String? = try await withCheckedThrowingContinuation { cont in
                FeedParser(data: data).parseAsync { result in
                    switch result {
                    case .success(let feed):
                        switch feed {
                        case .rss(let rss):   cont.resume(returning: rss.title)
                        case .atom(let atom): cont.resume(returning: atom.title)
                        case .json(let json): cont.resume(returning: json.title)
                        }
                    case .failure(let err):
                        cont.resume(throwing: err)
                    }
                }
            }

            fetchedTitle = title?.trimmingCharacters(in: .whitespacesAndNewlines)
                        ?? url.host
                        ?? urlString
            hasFetchedSuccessfully = true

        } catch {
            fetchError = "Couldn't read feed: \(error.localizedDescription)"
        }

        isFetching = false
    }

    /// Persists the feed (and optionally a new folder) to SwiftData, then dismisses.
    func subscribe(dismiss: () -> Void) async {
        guard canSubscribe else { return }
        isSaving = true
        saveError = nil

        do {
            // Create new folder inline if requested
            var folderID = selectedFolderID
            if isCreatingNewFolder {
                let name = newFolderName.trimmingCharacters(in: .whitespaces)
                guard !name.isEmpty else {
                    saveError = "Please enter a folder name."
                    isSaving = false
                    return
                }
                try SwiftDataService.shared.addFolder(name: name, iconName: newFolderIcon, colorHex: newFolderColorHex)
                // The newly created folder is the last one
                folderID = SwiftDataService.shared.categories.last?.id
            }

            let websiteURL = URL(string: normalizedURL)
                .flatMap { URL(string: "https://\($0.host ?? "")") }?
                .absoluteString ?? normalizedURL

            try SwiftDataService.shared.addFeed(
                feedURL:    normalizedURL,
                title:      displayTitle,
                websiteURL: websiteURL,
                folderID:   folderID
            )
            dismiss()

        } catch {
            saveError = "Failed to save: \(error.localizedDescription)"
        }

        isSaving = false
    }

    /// Resets all state so the sheet can be reused.
    func reset() {
        urlText              = ""
        selectedFolderID     = nil
        newFolderName        = ""
        newFolderIcon        = "folder.fill"
        newFolderColorHex    = "007AFF"
        isCreatingNewFolder  = false
        fetchedTitle         = ""
        isFetching           = false
        fetchError           = nil
        hasFetchedSuccessfully = false
        isSaving             = false
        saveError            = nil
    }
}
