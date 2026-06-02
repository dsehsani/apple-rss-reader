//
//  TutorialActivityAttributes.swift
//  Payam (shared with PayamTutorialWidget)
//
//  ActivityKit attributes describing the tutorial Live Activity state.
//  IMPORTANT: This file must have Target Membership in BOTH the Payam app
//  and the PayamTutorialWidget extension. In Xcode: select this file →
//  File Inspector (right pane) → Target Membership → check both boxes.
//

import Foundation
#if canImport(ActivityKit)
import ActivityKit
#endif

#if canImport(ActivityKit)
@available(iOS 16.2, *)
struct TutorialActivityAttributes: ActivityAttributes {

    /// Per-update content the system can re-render.
    public struct ContentState: Codable, Hashable {
        /// Stable ordered list of step IDs. Drives dot rendering order in
        /// the Dynamic Island. Index 0 is the leftmost dot.
        public var stepIDs: [String]

        /// IDs (subset of stepIDs) the user has already completed.
        public var completedIDs: Set<String>

        /// Title of the next pending step (shown in the DI expanded view).
        public var currentStepTitle: String

        public init(stepIDs: [String], completedIDs: Set<String>, currentStepTitle: String) {
            self.stepIDs = stepIDs
            self.completedIDs = completedIDs
            self.currentStepTitle = currentStepTitle
        }

        /// Convenience: number of completed steps.
        public var completedCount: Int { completedIDs.count }

        /// Convenience: total number of steps.
        public var totalCount: Int { stepIDs.count }
    }

    // Static attributes — none needed; the Live Activity is identified by its
    // singleton instance, not by an external identifier.
}
#endif
