//
//  TutorialLiveActivityController.swift
//  Payam
//
//  Thin wrapper around ActivityKit that drives the Dynamic Island tutorial
//  progress dots. Safe to call when the widget extension isn't installed
//  yet (start / update / end log and no-op rather than crash).
//

import Foundation
import OSLog

#if canImport(ActivityKit)
import ActivityKit
#endif

@available(iOS 16.2, *)
@Observable
final class TutorialLiveActivityController {

    static let shared = TutorialLiveActivityController()

    private let log = Logger(subsystem: "DariusEhsani.Payam", category: "TutorialLiveActivity")

    #if canImport(ActivityKit)
    private var activity: Activity<TutorialActivityAttributes>?
    #endif

    /// True when an Activity has been successfully requested and not yet ended.
    private(set) var isRunning: Bool = false

    /// True if the most recent `start()` attempt threw before the activity
    /// could be created. Cleared on the next successful start.
    private(set) var lastStartFailed: Bool = false

    /// Mirrors `ActivityAuthorizationInfo().areActivitiesEnabled`.
    /// Re-read on every access (the system can change this asynchronously).
    var areActivitiesEnabled: Bool {
        #if canImport(ActivityKit)
        return ActivityAuthorizationInfo().areActivitiesEnabled
        #else
        return false
        #endif
    }

    private init() {}

    // MARK: - Public API

    func start(completed: Set<TutorialManager.ChecklistItem>, currentTitle: String) {
        #if canImport(ActivityKit)
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            log.info("Live Activities disabled by user; tutorial DI skipped.")
            return
        }

        // If something is already running (e.g. from a prior session that
        // crashed before .end()), end it before starting fresh.
        if let existing = activity {
            Task {
                await existing.end(nil, dismissalPolicy: .immediate)
            }
            activity = nil
        }

        let state = TutorialActivityAttributes.ContentState(
            stepIDs: TutorialManager.ChecklistItem.allCases.map(\.id),
            completedIDs: Set(completed.map(\.id)),
            currentStepTitle: currentTitle
        )

        do {
            activity = try Activity.request(
                attributes: TutorialActivityAttributes(),
                content: ActivityContent(state: state, staleDate: nil),
                pushType: nil
            )
            isRunning = true
            lastStartFailed = false
            log.info("Started tutorial Live Activity.")
        } catch {
            isRunning = false
            lastStartFailed = true
            log.warning("Failed to start tutorial Live Activity: \(error.localizedDescription, privacy: .public)")
            // Most common failure: widget extension target not yet added.
            // We swallow the error — the in-app checklist still works.
        }
        #endif
    }

    func update(completed: Set<TutorialManager.ChecklistItem>, currentTitle: String) {
        #if canImport(ActivityKit)
        guard let activity else { return }
        let state = TutorialActivityAttributes.ContentState(
            stepIDs: TutorialManager.ChecklistItem.allCases.map(\.id),
            completedIDs: Set(completed.map(\.id)),
            currentStepTitle: currentTitle
        )
        Task {
            await activity.update(ActivityContent(state: state, staleDate: nil))
        }
        #endif
    }

    func end() {
        #if canImport(ActivityKit)
        guard let activity else { return }
        let final = activity.content.state
        Task {
            await activity.end(
                ActivityContent(state: final, staleDate: nil),
                dismissalPolicy: .immediate
            )
        }
        self.activity = nil
        isRunning = false
        log.info("Ended tutorial Live Activity.")
        #endif
    }
}
