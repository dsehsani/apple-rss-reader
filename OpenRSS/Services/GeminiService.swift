//
//  GeminiService.swift
//  OpenRSS
//
//  Local testing only — calls OpenAI ChatGPT API to power the in-app chat assistant.
//

import Foundation

enum GeminiService {

    static let apiKey = APIKeys.openAI

    private static let endpoint = "https://api.openai.com/v1/chat/completions"

    private static let baseSystemPrompt = """
    You are an AI assistant built into OpenRSS, a modern RSS reader app for iOS. You help users with three things:

    1. Summarizing articles — When the user is reading an article, summarize it clearly, highlight key points, and answer follow-up questions about its content based on the article context you are given.

    2. Recommending RSS feed URLs — When a user describes their interests, suggest specific real RSS feed URLs they can add to OpenRSS (e.g. https://feeds.npr.org/1001/rss.xml). Always provide actual feed URLs, not just website names.

    3. Explaining how to use OpenRSS — Help users navigate the app: adding feeds via the My Feeds tab, organizing feeds into folders, using the Today feed with category filters, bookmarking articles, browsing the Discover tab, and using app Settings.

    Keep responses concise and conversational. Use plain text; only use minimal formatting when it genuinely aids clarity.
    """

    static func send(
        history: [ChatMessage],
        articleContext: ChatViewModel.ArticleContext?
    ) async throws -> String {
        guard let url = URL(string: endpoint) else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let systemPrompt = buildSystemPrompt(articleContext: articleContext)

        var messages: [[String: Any]] = [
            ["role": "system", "content": systemPrompt]
        ]
        messages += history.map { msg in
            [
                "role": msg.role == .user ? "user" : "assistant",
                "content": msg.content
            ]
        }

        let body: [String: Any] = [
            "model": "gpt-4o-mini",
            "messages": messages
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw APIError.httpError(code)
        }

        guard
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let choices = json["choices"] as? [[String: Any]],
            let first = choices.first,
            let message = first["message"] as? [String: Any],
            let text = message["content"] as? String
        else {
            throw APIError.unexpectedResponse
        }

        return text
    }

    private static func buildSystemPrompt(articleContext: ChatViewModel.ArticleContext?) -> String {
        guard let ctx = articleContext else { return baseSystemPrompt }

        let snippet = String(ctx.content.prefix(3000))

        return """
        \(baseSystemPrompt)

        ---

        The user is currently reading an article in OpenRSS:

        Title: \(ctx.title)
        Feed: \(ctx.feedName)

        Article content:
        \(snippet)

        Reference this article when answering questions. If asked to summarize it, do so based on the content above.
        """
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
