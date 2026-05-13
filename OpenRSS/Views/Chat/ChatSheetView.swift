//
//  ChatSheetView.swift
//  OpenRSS
//
//  Modal chat interface powered by Gemini. Presented as a sheet from both
//  TodayView (no article context) and ArticleReaderHostView (article context set).
//

import SwiftUI

// MARK: - ChatSheetView

struct ChatSheetView: View {

    @Bindable var viewModel: ChatViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @FocusState private var isInputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            Divider().opacity(colorScheme == .dark ? 0.15 : 0.25)
            messageList
            Divider().opacity(colorScheme == .dark ? 0.15 : 0.25)
            inputBar
        }
        .background(Design.Colors.background(for: colorScheme).ignoresSafeArea())
    }

    // MARK: - Header

    private var headerBar: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Design.Colors.primary.opacity(0.12))
                    .frame(width: 36, height: 36)
                Image(systemName: "sparkles")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Design.Colors.primary)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("OpenRSS Assistant")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Design.Colors.primaryText(for: colorScheme))

                Text(viewModel.articleContext != nil ? "Article context loaded" : "Powered by ChatGPT")
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

    // MARK: - Message List

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    // Static welcome bubble — never sent to the API.
                    messageBubble(text: viewModel.welcomeMessage, role: .assistant)
                        .id("welcome")

                    ForEach(viewModel.messages) { msg in
                        messageBubble(text: msg.content, role: msg.role)
                            .id(msg.id)
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

                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .onChange(of: viewModel.messages.count) {
                withAnimation(Design.Animation.standard) { proxy.scrollTo("bottom") }
            }
            .onChange(of: viewModel.isLoading) {
                withAnimation(Design.Animation.standard) { proxy.scrollTo("bottom") }
            }
        }
    }

    /// Strips common markdown formatting from AI responses so they render as
    /// clean plain text — removes ** bold **, * italic *, and # header markers.
    private func strippingMarkdown(_ text: String) -> String {
        let lines = text.components(separatedBy: "\n").map { line in
            line.replacingOccurrences(of: #"^#{1,6}\s*"#, with: "", options: .regularExpression)
        }
        return lines.joined(separator: "\n")
            .replacingOccurrences(of: #"\*\*(.+?)\*\*"#, with: "$1", options: .regularExpression)
            .replacingOccurrences(of: #"\*(.+?)\*"#,    with: "$1", options: .regularExpression)
    }

    @ViewBuilder
    private func messageBubble(text: String, role: ChatMessage.Role) -> some View {
        HStack(alignment: .bottom, spacing: 0) {
            if role == .user { Spacer(minLength: 56) }

            Text(role == .assistant ? strippingMarkdown(text) : text)
                .font(.system(size: 15))
                .foregroundStyle(
                    role == .user
                        ? .white
                        : Design.Colors.primaryText(for: colorScheme)
                )
                .textSelection(.enabled)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(
                            role == .user
                                ? Design.Colors.primary
                                : Design.Colors.cardBackground(for: colorScheme)
                        )
                        .overlay {
                            if role == .assistant {
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(Design.Colors.glassBorder(for: colorScheme), lineWidth: 0.5)
                            }
                        }
                }
                .fixedSize(horizontal: false, vertical: true)

            if role == .assistant { Spacer(minLength: 56) }
        }
    }

    // MARK: - Input Bar

    private var inputBar: some View {
        HStack(spacing: 10) {
            TextField("Message...", text: $viewModel.inputText, axis: .vertical)
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

// MARK: - Typing Dots

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
