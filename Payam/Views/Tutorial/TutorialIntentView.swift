//
//  TutorialIntentView.swift
//  Payam
//
//  Intent personalization — asks the user which categories interest them so
//  Discover can re-order its recommended sources accordingly. Modeled on
//  Canva's "what will you design?" and Notion's "Work/Personal/School" screens.
//

import SwiftUI

struct TutorialIntentView: View {

    @Environment(\.colorScheme) private var colorScheme

    let onContinue: (Set<String>) -> Void
    let onSkip: () -> Void

    @State private var picked: Set<String> = []
    @State private var appeared = false

    /// Display name + SF Symbol pairs. The display name MUST match an entry in
    /// `RSSCatalog.categories[*].name` so Discover can use it to re-order
    /// recommended sections.
    private static let options: [(name: String, icon: String)] = [
        ("Tech",        "cpu"),
        ("Apple",       "apple.logo"),
        ("Programming", "terminal.fill"),
        ("Science",     "waveform"),
        ("News",        "newspaper.fill"),
        ("Gaming",      "gamecontroller.fill"),
        ("Music",       "music.note"),
        ("Business",    "briefcase.fill"),
        ("Startups",    "lightbulb.fill"),
        ("Space",       "moon.stars.fill"),
        ("iOS Dev",     "swift"),
        ("Books",       "books.vertical.fill"),
    ]

    private let columns: [GridItem] = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10),
    ]

    var body: some View {
        ZStack {
            Design.Colors.background(for: colorScheme).ignoresSafeArea()

            VStack(spacing: 0) {
                header
                    .padding(.top, 24)
                    .padding(.bottom, 20)

                ScrollView {
                    LazyVGrid(columns: columns, spacing: 10) {
                        ForEach(Self.options, id: \.name) { option in
                            chip(name: option.name, icon: option.icon)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 16)
                }

                Spacer(minLength: 0)

                footer
                    .padding(.bottom, 36)
            }
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 6)
            .onAppear {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) {
                    appeared = true
                }
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 10) {
            Text("What do you want to follow?")
                .font(.system(size: 26, weight: .bold))
                .multilineTextAlignment(.center)
                .foregroundStyle(Design.Colors.primaryText(for: colorScheme))
                .padding(.horizontal, 32)

            Text("Pick a few. We'll suggest sources in Discover.")
                .font(.system(size: 15))
                .multilineTextAlignment(.center)
                .foregroundStyle(Design.Colors.secondaryText(for: colorScheme))
                .padding(.horizontal, 40)
        }
    }

    // MARK: - Chip

    private func chip(name: String, icon: String) -> some View {
        let selected = picked.contains(name)
        return Button {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
                if selected {
                    picked.remove(name)
                } else {
                    picked.insert(name)
                }
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(selected ? .white : Design.Colors.primary)
                    .frame(width: 22, height: 22)

                Text(name)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(
                        selected ? .white : Design.Colors.primaryText(for: colorScheme)
                    )
                    .lineLimit(1)

                Spacer(minLength: 0)

                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 16))
                    .foregroundStyle(
                        selected
                            ? .white.opacity(0.95)
                            : Design.Colors.secondaryText(for: colorScheme).opacity(0.5)
                    )
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(
                        selected
                            ? AnyShapeStyle(Design.Colors.primary)
                            : AnyShapeStyle(Design.Colors.cardBackground(for: colorScheme))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(
                                selected
                                    ? Color.clear
                                    : Design.Colors.glassBorder(for: colorScheme),
                                lineWidth: 0.5
                            )
                    )
                    .shadow(
                        color: selected
                            ? Design.Colors.primary.opacity(0.30)
                            : .clear,
                        radius: 8, y: 3
                    )
            )
            .scaleEffect(selected ? 1.02 : 1.0)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(spacing: 12) {
            Button {
                onContinue(picked)
            } label: {
                Text("Continue")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background(
                        Capsule()
                            .fill(picked.isEmpty
                                ? Design.Colors.primary.opacity(0.35)
                                : Design.Colors.primary)
                            .shadow(
                                color: picked.isEmpty
                                    ? .clear
                                    : Design.Colors.primary.opacity(0.45),
                                radius: 14, y: 5
                            )
                    )
            }
            .buttonStyle(.plain)
            .disabled(picked.isEmpty)
            .padding(.horizontal, 24)
            .animation(Design.Animation.quick, value: picked.isEmpty)

            Button(action: onSkip) {
                Text("Skip")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Design.Colors.secondaryText(for: colorScheme))
                    .frame(height: 32)
            }
            .buttonStyle(.plain)
        }
    }
}

#Preview {
    TutorialIntentView(onContinue: { _ in }, onSkip: {})
}
