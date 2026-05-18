//
//  ChatViewModel.swift
//  OpenRSS
//

import Foundation

@Observable final class ChatViewModel {

    var messages: [ChatMessage] = []
    var inputText: String = ""
    var isLoading = false
    var errorMessage: String? = nil
    private(set) var articleContext: ArticleContext? = nil

    struct ArticleContext {
        let title: String
        let feedName: String
        let content: String
    }

    // Static UI-only welcome message shown at the top of every chat session.
    // Never sent to the API — history always starts with a real user turn.
    var welcomeMessage: String {
        if let ctx = articleContext {
            return "I can see you're reading \"\(ctx.title)\". Ask me to summarize it, or ask anything!"
        }
        return "Hi! I'm your OpenRSS assistant. I can summarize articles, suggest RSS feeds, or help you use the app."
    }

    // Called once after the article pipeline finishes loading. Extracts plain text
    // from the content nodes and stores it for Gemini context injection.
    func setArticleContext(title: String, feedName: String, nodes: [ContentNode]) {
        guard articleContext == nil else { return }
        let plainText = nodes.compactMap { node -> String? in
            switch node {
            case .heading(_, let t):   return t
            case .paragraph(let t):    return t
            case .blockquote(let t):   return t
            case .codeBlock(let t):    return t
            case .list(let items, _):  return items.joined(separator: "\n")
            case .table(let h, let r): return (h + r.flatMap { $0 }).joined(separator: " ")
            case .image, .videoEmbed:  return nil
            }
        }.joined(separator: "\n\n")
        articleContext = ArticleContext(title: title, feedName: feedName, content: plainText)
    }

    @MainActor
    func send() async {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isLoading else { return }

        inputText = ""
        errorMessage = nil
        messages.append(ChatMessage(role: .user, content: text))
        isLoading = true

        do {
            let reply = try await GeminiService.send(
                history: messages,
                articleContext: articleContext
            )
            messages.append(ChatMessage(role: .assistant, content: reply))
        } catch {
            // Remove the unanswered user message so history stays in valid user/model alternation.
            messages.removeLast()
            inputText = text
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }
}
