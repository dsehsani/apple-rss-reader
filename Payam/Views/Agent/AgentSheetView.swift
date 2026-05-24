//
//  AgentSheetView.swift
//  Payam
//
//  The action-first agent UI. Replaces the legacy ChatSheetView's bubble layout
//  with a typed-component renderer: each agent turn is shown as the SwiftUI view
//  associated with its `AgentView` case.
//
//  Presented from TodayView (no article context) and ArticleReaderHostView
//  (article context set via setArticleContext on the AgentViewModel).
//

import SwiftUI

// MARK: - AgentSheetView

struct AgentSheetView: View {

    @Bindable var viewModel: AgentViewModel

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @FocusState private var isInputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            Divider().opacity(colorScheme == .dark ? 0.15 : 0.25)

            if let banner = viewModel.quotaBanner {
                quotaBannerView(banner)
                Divider().opacity(colorScheme == .dark ? 0.15 : 0.25)
            }

            turnList
            Divider().opacity(colorScheme == .dark ? 0.15 : 0.25)
            inputBar
        }
        .background(Design.Colors.background(for: colorScheme).ignoresSafeArea())
    }

    // MARK: - Header

    private var headerBar: some View {
        HStack(spacing: 12) {
            Image("DiscoverAgentLogo")
                .renderingMode(.original)
                .resizable()
                .scaledToFill()
                .frame(width: 36, height: 36)
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text("Payam Assistant")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Design.Colors.primaryText(for: colorScheme))

                Text(viewModel.articleContext != nil ? "Article context loaded" : "Action-first agent")
                    .font(.system(size: 11))
                    .foregroundStyle(
                        viewModel.articleContext != nil
                            ? Design.Colors.primary.opacity(0.8)
                            : Design.Colors.secondaryText(for: colorScheme)
                    )
            }

            Spacer()

            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Design.Colors.secondaryText(for: colorScheme))
                    .glassButton(size: 28, colorScheme: colorScheme)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 14)
    }

    // MARK: - Quota banner

    private func quotaBannerView(_ text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "hourglass")
                .font(.system(size: 12, weight: .semibold))
            Text(text)
                .font(.system(size: 13))
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .foregroundStyle(.orange)
        .background(Color.orange.opacity(0.08))
    }

    // MARK: - Turn list

    private var turnList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    // Static welcome bubble — UI-only, never sent back to the server.
                    welcomeView
                        .id("welcome")

                    ForEach(viewModel.turns) { turn in
                        turnView(turn)
                            .id(turn.id)
                    }

                    if viewModel.isLoading {
                        TypingDotsView(colorScheme: colorScheme)
                            .id("typing")
                    }

                    if let err = viewModel.errorMessage {
                        Label(err, systemImage: "exclamationmark.triangle.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(.orange)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                            .id("error")
                    }

                    if let last = viewModel.turns.last,
                       case .agent(let t) = last,
                       !t.envelope.followups.isEmpty {
                        followupChips(t.envelope.followups)
                    }

                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .onChange(of: viewModel.turns.count) {
                withAnimation(Design.Animation.standard) { proxy.scrollTo("bottom") }
            }
            .onChange(of: viewModel.isLoading) {
                withAnimation(Design.Animation.standard) { proxy.scrollTo("bottom") }
            }
        }
    }

    // MARK: - Per-turn rendering

    @ViewBuilder
    private func turnView(_ turn: AgentViewModel.Turn) -> some View {
        switch turn {
        case .user(let t):
            userBubble(text: t.text)
        case .agent(let t):
            agentTurnView(t.envelope)
        }
    }

    @ViewBuilder
    private func agentTurnView(_ envelope: AgentEnvelope) -> some View {
        switch envelope.view {
        case .text(let payload):
            assistantBubble(text: payload.content)
        case .cardList(let payload):
            SourceDiscoveryCardListView(payload: payload)
        case .ruleCard(let payload):
            FilterRuleCardView(payload: payload)
        case .triageList:
            assistantBubble(text: "Feed audit coming soon — for now I can find new sources or set up filter rules.")
        case .summaryCard(let payload):
            assistantBubble(text: payload.bullets.joined(separator: "\n• "))
        case .unknown(let typeName):
            assistantBubble(text: "Update Payam to see this response (unknown view: \(typeName)).")
        }
    }

    // MARK: - Welcome

    private var welcomeView: some View {
        assistantBubble(text: viewModel.welcomeMessage)
    }

    // MARK: - User & assistant bubbles (text-only path)

    private func userBubble(text: String) -> some View {
        HStack(spacing: 0) {
            Spacer(minLength: 56)
            Text(text)
                .font(.system(size: 15))
                .foregroundStyle(.white)
                .textSelection(.enabled)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Design.Colors.primary)
                }
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func assistantBubble(text: String) -> some View {
        HStack(alignment: .bottom, spacing: 0) {
            Text(text)
                .font(.system(size: 15))
                .foregroundStyle(Design.Colors.primaryText(for: colorScheme))
                .textSelection(.enabled)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Design.Colors.cardBackground(for: colorScheme))
                        .overlay {
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(Design.Colors.glassBorder(for: colorScheme), lineWidth: 0.5)
                        }
                }
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 56)
        }
    }

    // MARK: - Followup chips

    private func followupChips(_ chips: [String]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(chips, id: \.self) { chip in
                    Button {
                        Task { await viewModel.runFollowup(chip) }
                    } label: {
                        Text(chip)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Design.Colors.primary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(Design.Colors.primary.opacity(0.10), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 2)
        }
    }

    // MARK: - Input bar

    private var inputBar: some View {
        HStack(spacing: 10) {
            TextField("Try \u{201C}find me feeds about…\u{201D}", text: $viewModel.inputText, axis: .vertical)
                .font(.system(size: 15))
                .foregroundStyle(Design.Colors.primaryText(for: colorScheme))
                .lineLimit(1...5)
                .focused($isInputFocused)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Design.Colors.cardBackground(for: colorScheme), in: RoundedRectangle(cornerRadius: 12))
                .overlay {
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Design.Colors.glassBorder(for: colorScheme), lineWidth: 0.5)
                }

            Button {
                Task { await viewModel.send() }
            } label: {
                let ready = !viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                             && !viewModel.isLoading
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(
                        ready
                            ? Design.Colors.primary
                            : Design.Colors.secondaryText(for: colorScheme).opacity(0.35)
                    )
                    .animation(Design.Animation.quick, value: ready)
            }
            .buttonStyle(.plain)
            .disabled(
                viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || viewModel.isLoading
            )
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Design.Colors.background(for: colorScheme))
    }
}

// MARK: - Typing dots (mirrors ChatSheetView's behaviour)

private struct TypingDotsView: View {
    let colorScheme: ColorScheme
    @State private var phase = 0

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(Design.Colors.secondaryText(for: colorScheme))
                    .frame(width: 6, height: 6)
                    .opacity(phase == i ? 1 : 0.3)
            }
        }
        .animation(Design.Animation.quick, value: phase)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background {
            RoundedRectangle(cornerRadius: 16)
                .fill(Design.Colors.cardBackground(for: colorScheme))
                .overlay {
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Design.Colors.glassBorder(for: colorScheme), lineWidth: 0.5)
                }
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 350_000_000)
                phase = (phase + 1) % 3
            }
        }
    }
}
