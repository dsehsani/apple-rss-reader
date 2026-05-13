//
//  GeminiService.swift
//  OpenRSS
//
//  Calls the payam-chat Lambda (POST /v1/chat) to power the in-app chat assistant.
//

import Foundation

enum GeminiService {

    private static var chatEndpoint: URL? {
        var base = APIKeys.payamChatBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        while base.hasSuffix("/") {
            base.removeLast()
        }
        guard !base.isEmpty else { return nil }
        return URL(string: base + "/v1/chat")
    }

    static func send(
        history: [ChatMessage],
        articleContext: ChatViewModel.ArticleContext?
    ) async throws -> String {
        guard let url = chatEndpoint else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        var messages: [[String: Any]] = history.map { msg in
            [
                "role": msg.role == .user ? "user" : "assistant",
                "content": msg.content
            ]
        }

        var body: [String: Any] = ["messages": messages]
        if let ctx = articleContext {
            body["articleContext"] = [
                "title": ctx.title,
                "feedName": ctx.feedName,
                "content": ctx.content
            ]
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw APIError.httpError(code)
        }

        guard
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let text = json["reply"] as? String
        else {
            throw APIError.unexpectedResponse
        }

        return text
    }

    enum APIError: LocalizedError {
        case invalidURL
        case httpError(Int)
        case unexpectedResponse

        var errorDescription: String? {
            switch self {
            case .invalidURL:           return "Invalid API URL."
            case .httpError(let code):  return "API error (HTTP \(code)). Check your API key."
            case .unexpectedResponse:   return "Unexpected response from the API."
            }
        }
    }
}
