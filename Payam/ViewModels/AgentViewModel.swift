//
//  AgentViewModel.swift
//  Payam
//
//  Replacement for ChatViewModel. Drives the action-first agent sheet: the user
//  types a message and the response is rendered as a typed UI component (card list,
//  rule card, etc.), not a chat bubble.
//
//  Turns are kept in chronological order. A user turn contains the typed text; an
//  agent turn contains the AgentEnvelope so the view layer can switch on view type.
//

import Foundation

@Observable final class AgentViewModel {

    // MARK: - Turn model

    struct UserTurn: Identifiable {
        let id = UUID()
        let text: String
    }

    struct AgentTurn: Identifiable {
        let id = UUID()
        let envelope: AgentEnvelope
    }

    enum Turn: Identifiable {
        case user(UserTurn)
        case agent(AgentTurn)

        var id: UUID {
            switch self {
            case .user(let t):  return t.id
            case .agent(let t): return t.id
            }
        }
    }

    // MARK: - Published state

    var turns: [Turn] = []
    var inputText: String = ""
    var isLoading = false
    var errorMessage: String? = nil

    /// Quota banner content; populated from the last envelope's `quota` field.
    /// Views read this; nil means no banner.
    var quotaBanner: String? = nil

    private(set) var articleContext: AgentClient.ArticleContext? = nil

    /// Closure the view layer supplies so the VM can fetch current subscriptions
    /// without coupling to SwiftDataService directly (keeps testability).
    var subscriptionsProvider: () -> [AgentClient.SubscriptionRef] = { [] }

    // MARK: - Welcome

    /// Static UI-only welcome shown above the first turn.
    var welcomeMessage: String {
        if let ctx = articleContext {
            return "I see you're reading \u{201C}\(ctx.title)\u{201D}. Ask me to summarize it, find similar feeds, or anything else."
        }
        return "Try \u{201C}find me feeds about iOS dev\u{201D} or \u{201C}stop showing me opinion pieces.\u{201D}"
    }

    // MARK: - Article context injection

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
        articleContext = AgentClient.ArticleContext(
            title: title,
            feedName: feedName,
            content: plainText
        )
    }

    // MARK: - Send

    @MainActor
    func send() async {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isLoading else { return }

        inputText = ""
        errorMessage = nil

        let userTurn = UserTurn(text: text)
        turns.append(.user(userTurn))
        isLoading = true

        // Build the chat history we send to the agent. Mix user turns and assistant
        // text-view turns; non-text agent views are converted to a brief stand-in so
        // the model has a coherent transcript (e.g. "[5 feed cards shown]").
        let history = buildHistory()

        let subscriptions = subscriptionsProvider()

        do {
            let envelope = try await AgentClient.send(
                history: history,
                articleContext: articleContext,
                subscriptions: subscriptions
            )
            turns.append(.agent(AgentTurn(envelope: envelope)))
            updateQuotaBanner(from: envelope.quota)
        } catch {
            // Roll the user turn back so re-sending isn't double-counted.
            turns.removeAll { if case .user(let t) = $0, t.id == userTurn.id { return true }; return false }
            inputText = text
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    // MARK: - Followup chips

    /// Convenience: run a followup chip as if the user had typed it.
    @MainActor
    func runFollowup(_ text: String) async {
        inputText = text
        await send()
    }

    // MARK: - Internals

    private func buildHistory() -> [ChatMessage] {
        var out: [ChatMessage] = []
        for turn in turns {
            switch turn {
            case .user(let t):
                out.append(ChatMessage(role: .user, content: t.text))
            case .agent(let t):
                out.append(ChatMessage(role: .assistant, content: assistantStandIn(for: t.envelope)))
            }
        }
        return out
    }

    /// A short text stand-in for non-text agent turns so the model sees coherent
    /// history. Long card payloads aren't useful to replay; the intent + a summary is.
    private func assistantStandIn(for envelope: AgentEnvelope) -> String {
        switch envelope.view {
        case .text(let p):
            return p.content
        case .cardList(let list):
            return "[Showed \(list.cards.count) feed suggestions for \(list.topic).]"
        case .ruleCard(let card):
            return "[Proposed filter rule: \(card.displayText).]"
        case .triageList(let list):
            return "[Showed an audit of \(list.rows.count) feeds.]"
        case .summaryCard(let card):
            return "[Summarized: \(card.title).]"
        case .unknown(let typeName):
            return "[Returned an unknown view: \(typeName).]"
        }
    }

    private func updateQuotaBanner(from quota: AgentQuota?) {
        guard let quota else {
            quotaBanner = nil
            return
        }
        if quota.remaining <= 5 {
            quotaBanner = "Only \(quota.remaining) AI actions left this month."
        } else {
            quotaBanner = nil
        }
    }
}
