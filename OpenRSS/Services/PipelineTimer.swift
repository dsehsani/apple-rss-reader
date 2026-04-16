//
//  PipelineTimer.swift
//  OpenRSS
//
//  Phase 2a — Lightweight instrumentation for pipeline stage timing.
//  Logs each stage duration and total cycle time to verify <150ms target.
//

import Foundation
import os.log

// MARK: - PipelineTimer

final class PipelineTimer: Sendable {

    private let logger = Logger(subsystem: "com.openrss", category: "Pipeline")

    /// Times a single stage, logging the result.
    /// Returns the stage result and elapsed milliseconds.
    func time<T>(_ stageName: String, _ work: () throws -> T) rethrows -> (result: T, ms: Double) {
        let start = CFAbsoluteTimeGetCurrent()
        let result = try work()
        let elapsed = (CFAbsoluteTimeGetCurrent() - start) * 1000
        logger.info("[\(stageName)] \(String(format: "%.1f", elapsed))ms")
        return (result, elapsed)
    }

    /// Async version of stage timing.
    func time<T>(_ stageName: String, _ work: () async throws -> T) async rethrows -> (result: T, ms: Double) {
        let start = CFAbsoluteTimeGetCurrent()
        let result = try await work()
        let elapsed = (CFAbsoluteTimeGetCurrent() - start) * 1000
        logger.info("[\(stageName)] \(String(format: "%.1f", elapsed))ms")
        return (result, elapsed)
    }

    /// Logs total pipeline duration with a warning if it exceeds the target.
    func logTotal(_ totalMs: Double, itemCount: Int) {
        if totalMs > 150 {
            logger.warning("Pipeline EXCEEDED target: \(String(format: "%.1f", totalMs))ms for \(itemCount) items (target: <150ms)")
        } else {
            logger.info("Pipeline completed: \(String(format: "%.1f", totalMs))ms for \(itemCount) items")
        }
    }
}
