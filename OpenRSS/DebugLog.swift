//
//  DebugLog.swift
//  OpenRSS
//
//  TEMPORARY debug instrumentation for session d1840d.
//  Writes NDJSON lines to a fixed host path so the agent can read them
//  after the user reproduces a bug.
//
//  This file is intended to be removed after the investigation is complete.
//

import Foundation

enum DebugLog {

    private static let sessionId = "d1840d"

    private static let logURL: URL = URL(fileURLWithPath:
        "/Users/dariusehsani/Documents/ECS 193/OpenRSS/OpenRSS/.cursor/debug-d1840d.log"
    )

    /// Fallback path inside the app's Documents directory — used if writing
    /// to the absolute host path is blocked by the simulator sandbox.
    private static let fallbackURL: URL = {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return dir.appendingPathComponent("debug-d1840d.log")
    }()

    private static let queue = DispatchQueue(label: "openrss.debug.log", qos: .utility)

    /// Append a single NDJSON line.
    /// - Parameters:
    ///   - hypothesisId: which hypothesis this log tests (e.g. "H1", "H2").
    ///   - location: source-code location, e.g. "SwiftDataService.swift:467".
    ///   - message: short human-readable description.
    ///   - data: any JSON-serialisable payload.
    static func log(_ hypothesisId: String,
                    _ location: String,
                    _ message: String,
                    _ data: [String: Any] = [:]) {
        let timestamp = Int(Date().timeIntervalSince1970 * 1000)
        let id = "log_\(timestamp)_\(UUID().uuidString.prefix(6))"

        let safeData = sanitize(data)
        let entry: [String: Any] = [
            "sessionId": sessionId,
            "id": id,
            "timestamp": timestamp,
            "location": location,
            "hypothesisId": hypothesisId,
            "message": message,
            "data": safeData
        ]

        queue.async {
            guard
                let json = try? JSONSerialization.data(withJSONObject: entry, options: []),
                var line = String(data: json, encoding: .utf8)
            else { return }
            line.append("\n")
            let bytes = Data(line.utf8)

            // Simulator sandbox cannot write to the host `.cursor` path; POST to the
            // debug ingest server so NDJSON lands on the developer machine.
            postToIngest(json)

            #if DEBUG
            print("[agent-debug]", line.trimmingCharacters(in: .newlines))
            #endif

            if !append(bytes, to: logURL) {
                _ = append(bytes, to: fallbackURL)
            }
        }
    }

    /// Sends one JSON payload to the Cursor debug ingest endpoint (Mac localhost).
    private static func postToIngest(_ jsonData: Data) {
        guard let url = URL(string: "http://127.0.0.1:7851/ingest/480a1ef3-192a-4634-b783-fe8376980897") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(sessionId, forHTTPHeaderField: "X-Debug-Session-Id")
        req.httpBody = jsonData
        URLSession.shared.dataTask(with: req).resume()
    }

    // MARK: - Private

    /// Drops non-JSON-serialisable values so JSONSerialization can't crash.
    private static func sanitize(_ data: [String: Any]) -> [String: Any] {
        var out: [String: Any] = [:]
        for (k, v) in data {
            if JSONSerialization.isValidJSONObject([k: v]) {
                out[k] = v
            } else {
                out[k] = String(describing: v)
            }
        }
        return out
    }

    /// Append `bytes` to `url`. Returns `true` on success.
    @discardableResult
    private static func append(_ bytes: Data, to url: URL) -> Bool {
        let fm = FileManager.default
        if !fm.fileExists(atPath: url.path) {
            // Best-effort directory creation.
            try? fm.createDirectory(at: url.deletingLastPathComponent(),
                                    withIntermediateDirectories: true)
            return (try? bytes.write(to: url)) != nil
        }
        guard let handle = try? FileHandle(forWritingTo: url) else { return false }
        defer { try? handle.close() }
        do {
            try handle.seekToEnd()
            try handle.write(contentsOf: bytes)
            return true
        } catch {
            return false
        }
    }
}
