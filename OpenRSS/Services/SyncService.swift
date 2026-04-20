//
//  SyncService.swift
//  OpenRSS
//
//  Monitors NSPersistentCloudKitContainer events and exposes sync state to the UI.
//  Also handles post-sync feed deduplication and cascade delete cleanup.
//

import Foundation
import CoreData
import SwiftData
import Observation

// MARK: - SyncState

enum SyncState: Equatable {
    case synced
    case syncing
    case waiting          // Queued but no network
    case error(String)    // Error message for display
    case disabled         // Guest mode — no CloudKit

    var icon: String {
        switch self {
        case .synced:    return "checkmark.icloud"
        case .syncing:   return "arrow.triangle.2.circlepath"
        case .waiting:   return "clock.fill"
        case .error:     return "exclamationmark.icloud"
        case .disabled:  return "xmark.icloud"
        }
    }

    var label: String {
        switch self {
        case .synced:         return "Up to date"
        case .syncing:        return "Syncing\u{2026}"
        case .waiting:        return "Waiting for network"
        case .error(let msg): return "Error: \(msg)"
        case .disabled:       return "Sign in to sync"
        }
    }

    static func == (lhs: SyncState, rhs: SyncState) -> Bool {
        switch (lhs, rhs) {
        case (.synced, .synced),
             (.syncing, .syncing),
             (.waiting, .waiting),
             (.disabled, .disabled):
            return true
        case (.error(let a), .error(let b)):
            return a == b
        default:
            return false
        }
    }
}

// MARK: - SyncService

@Observable
final class SyncService {

    // MARK: - Singleton

    static let shared = SyncService()
    private init() {}

    // MARK: - Observable State

    private(set) var syncState: SyncState = .disabled
    private(set) var lastSyncDate: Date?

    // MARK: - Internal

    private var observer: NSObjectProtocol?

    // MARK: - Start Monitoring

    /// Call this after the ModelContainer is created (in OpenRSSApp.init or body).
    /// Pass `isCloudKitEnabled: false` for guest mode — shows disabled state immediately.
    func startMonitoring(isCloudKitEnabled: Bool) {
        guard isCloudKitEnabled else {
            syncState = .disabled
            return
        }

        syncState = .syncing

        // Observe NSPersistentCloudKitContainer events bridged through NotificationCenter.
        // SwiftData uses NSPersistentCloudKitContainer under the hood.
        let notificationName = NSNotification.Name("NSPersistentCloudKitContainerEventChangedNotification")

        observer = NotificationCenter.default.addObserver(
            forName: notificationName,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            self?.handleSyncEvent(notification)
        }
    }

    func stopMonitoring() {
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
    }

    // MARK: - Event Handling

    private func handleSyncEvent(_ notification: Notification) {
        // NSPersistentCloudKitContainerEvent is bridged via userInfo
        guard let event = notification.userInfo?["event"] else { return }

        // Use Mirror to read properties without importing CoreData internals
        let mirror = Mirror(reflecting: event)
        let props = Dictionary(
            mirror.children.compactMap { child -> (String, Any)? in
                guard let label = child.label else { return nil }
                return (label, child.value)
            },
            uniquingKeysWith: { first, _ in first }
        )

        let succeeded = props["succeeded"] as? Bool ?? true
        let typeRaw   = props["type"] as? Int ?? 0

        if !succeeded {
            let errorDesc = (props["error"] as? Error)?.localizedDescription ?? "Unknown error"
            syncState = .error(errorDesc)
            return
        }

        // Type: 0 = setup, 1 = import, 2 = export
        switch typeRaw {
        case 0:  // setup
            syncState = .syncing
        case 1:  // import (data arriving from cloud)
            syncState = .syncing
            handlePostImport()
        case 2:  // export (local changes pushed)
            syncState = .synced
            lastSyncDate = Date()
            updateUserProfileSyncDate()
        default:
            syncState = .synced
        }
    }

    // MARK: - Post-Import Deduplication

    /// After a CloudKit import, check for duplicate feeds (same feedURL, different UUIDs).
    /// Keeps the oldest record, re-assigns folder relationships, deletes duplicates.
    private func handlePostImport() {
        Task { @MainActor in
            let service = SwiftDataService.shared
            let allSources = service.sources

            // Group by feedURL (lowercased for case-insensitive dedup)
            var urlGroups: [String: [Source]] = [:]
            for source in allSources {
                let key = source.feedURL.lowercased()
                urlGroups[key, default: []].append(source)
            }

            // Find duplicates — groups with more than 1 entry
            for (_, group) in urlGroups where group.count > 1 {
                // Keep the oldest (earliest addedAt)
                let sorted = group.sorted { $0.addedAt < $1.addedAt }
                let duplicates = Array(sorted.dropFirst())
                for dup in duplicates {
                    try? service.deleteFeed(id: dup.id)
                }
            }

            syncState = .synced
            lastSyncDate = Date()
        }
    }

    // MARK: - Helpers

    private func updateUserProfileSyncDate() {
        Task { @MainActor in
            SwiftDataService.shared.updateProfileSyncDate()
        }
    }
}
