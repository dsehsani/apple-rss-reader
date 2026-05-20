//
//  AgentClient.swift
//  Payam
//
//  Replaces the legacy GeminiService for the new action-first agent.
//  POSTs to /v1/agent with messages, optional articleContext, and the user's
//  current subscriptions (so the backend can avoid suggesting duplicates and
//  scope filter rules accurately). Returns a typed AgentEnvelope.
//

import Foundation

enum AgentClient {

    // MARK: - Endpoint

    private static var endpoint: URL? {
        var base = APIKeys.payamChatBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        while base.hasSuffix("/") { base.removeLast() }
        guard !base.isEmpty else { return nil }
        return URL(string: base + "/v1/agent")
    }

    // MARK: - Request shape

    /// Lightweight subscription descriptor sent to the backend.
    /// Kept intentionally small — `feedURL` is the only field the agent reasons over.
    struct SubscriptionRef: Encodable {
        let title: String
        let feedURL: String
    }

    struct ArticleContext: Encodable {
        let title: String
        let feedName: String
        let content: String
    }

    private struct RequestBody: Encodable {
        let messages: [Message]
        let articleContext: ArticleContext?
        let subscriptions: [SubscriptionRef]

        struct Message: Encodable {
            let role: String
            let content: String
        }
    }

    // MARK: - Errors

    enum AgentError: LocalizedError {
        case invalidURL
        case http(Int, String?)
        case decoding(String)
        case transport(Error)

        var errorDescription: String? {
            switch self {
            case .invalidURL:                return "Agent endpoint isn't configured."
            case .http(let code, let msg):   return "Agent error (HTTP \(code))" + (msg.map { ": \($0)" } ?? "")
            case .decoding(let detail):      return "Couldn't parse agent response: \(detail)"
            case .transport(let err):        return err.localizedDescription
            }
        }
    }

    // MARK: - Send

    static func send(
        history: [ChatMessage],
        articleContext: ArticleContext?,
        subscriptions: [SubscriptionRef]
    ) async throws -> AgentEnvelope {

        guard let url = endpoint else { throw AgentError.invalidURL }

        let messages = history.map { msg in
            RequestBody.Message(
                role: msg.role == .user ? "user" : "assistant",
                content: msg.content
            )
        }

        let body = RequestBody(
            messages: messages,
            articleContext: articleContext,
            subscriptions: subscriptions
        )

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        request.timeoutInterval = 30

        // Attach JWT for tier enforcement and quota tracking
        if let jwt = KeychainService.loadJWT() {
            request.setValue("Bearer \(jwt)", forHTTPHeaderField: "Authorization")
        }

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw AgentError.transport(error)
        }

        guard let http = response as? HTTPURLResponse else {
            throw AgentError.http(0, nil)
        }

        guard (200..<300).contains(http.statusCode) else {
            // Try to surface a structured error envelope first; fall back to plain HTTP code.
            if let payload = try? JSONDecoder().decode([String: String].self, from: data),
               let msg = payload["error"] {
                throw AgentError.http(http.statusCode, msg)
            }
            throw AgentError.http(http.statusCode, nil)
        }

        do {
            return try JSONDecoder().decode(AgentEnvelope.self, from: data)
        } catch {
            throw AgentError.decoding(String(describing: error))
        }
    }
}
