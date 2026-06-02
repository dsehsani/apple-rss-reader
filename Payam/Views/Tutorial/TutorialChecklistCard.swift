//
//  TutorialChecklistCard.swift
//  Payam
//
//  Persistent onboarding card pinned at the top via .safeAreaInset (set up
//  in MainTabView). Compact form is a quiet single-line status pill;
//  expanded form is the full Notion-style checklist with an "End tour" menu.
//
//  Compact pill:    [badge] step title              [chevron▼]
//  Expanded card:   [badge] Get started with Payam  1/3  [...] [chevron▲]
//                   ━━━━━━━━━░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
//                   [○] Create a folder            ▶
//                   [○] Select a feed from Discover ▶
//                   [○] Read your feed             ▶
//

import SwiftUI

struct TutorialChecklistCard: View {

    @Environment(\.colorScheme) private var colorScheme
    @Environment(AppState.self) private var appState

    let tutorial: TutorialManager

    /// Snapshot read from the parent so the @Observable mutations re-render.
    let completedItems: Set<TutorialManager.ChecklistItem>
    let expanded: Bool

    var body: some View {
        VStack(spacing: 0) {
            if expanded {
                expandedHeader
                    .contentShape(Rectangle())
                    .onTapGesture { tutorial.toggleChecklistExpanded() }

                Divider()
                    .background(Color.primary.opacity(0.08))
                    .padding(.horizontal, 14)

                VStack(spacing: 6) {
                    ForEach(TutorialManager.ChecklistItem.allCases) { item in
                        row(item)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .move(edge: .top)),
                    removal: .opacity
                ))
            } else {
                compactPill
                    .contentShape(Rectangle())
                    .onTapGesture { tutorial.toggleChecklistExpanded() }
            }
        }
        .background(card)
    }

    // MARK: - Compact pill (collapsed)

    private var compactPill: some View {
        HStack(spacing: 12) {
            badgeIcon

            Text(currentStepTitle)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Design.Colors.primaryText(for: colorScheme))
                .lineLimit(1)

            Spacer(minLength: 4)

            // Three step dots — one per checklist item, green once completed.
            compactDots

            Image(systemName: "chevron.down")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Design.Colors.secondaryText(for: colorScheme))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }

    private var compactDots: some View {
        HStack(spacing: 5) {
            ForEach(Array(TutorialManager.ChecklistItem.allCases.enumerated()), id: \.element) { _, item in
                Circle()
                    .fill(completedItems.contains(item)
                          ? AnyShapeStyle(Color.green)
                          : AnyShapeStyle(Color.clear))
                    .overlay(
                        Circle()
                            .stroke(
                                completedItems.contains(item)
                                    ? Color.green
                                    : Design.Colors.secondaryText(for: colorScheme).opacity(0.45),
                                style: StrokeStyle(
                                    lineWidth: 1.2,
                                    dash: completedItems.contains(item) ? [] : [2, 1.6]
                                )
                            )
                    )
                    .frame(width: 8, height: 8)
                    .animation(.spring(response: 0.45, dampingFraction: 0.78),
                               value: completedItems)
            }
        }
    }

    // MARK: - Expanded header

    private var expandedHeader: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                badgeIcon

                Text("Get started with Payam")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Design.Colors.primaryText(for: colorScheme))
                    .lineLimit(1)

                Spacer(minLength: 8)

                Text("\(tutorial.progress.done) / \(tutorial.progress.total)")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Design.Colors.secondaryText(for: colorScheme))
                    .monospacedDigit()

                // Subtle close — ends the tour directly (no menu).
                Button {
                    tutorial.finish()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Design.Colors.secondaryText(for: colorScheme).opacity(0.7))
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Image(systemName: "chevron.up")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Design.Colors.secondaryText(for: colorScheme))
            }

            progressBar
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }

    private var progressBar: some View {
        GeometryReader { geo in
            let fraction = Double(tutorial.progress.done) / Double(max(tutorial.progress.total, 1))
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.primary.opacity(0.10))
                    .frame(height: 4)
                Capsule()
                    .fill(Design.Colors.primary)
                    .frame(width: geo.size.width * fraction, height: 4)
                    .animation(.spring(response: 0.5, dampingFraction: 0.78),
                               value: tutorial.progress.done)
            }
        }
        .frame(height: 4)
    }

    // MARK: - Row (expanded)

    private func row(_ item: TutorialManager.ChecklistItem) -> some View {
        let isDone = completedItems.contains(item)
        let isNext = tutorial.nextItem == item
        return Button {
            tutorial.tapChecklistItem(item, appState: appState)
        } label: {
            HStack(spacing: 12) {
                stepIcon(for: item, isDone: isDone, isNext: isNext)

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(.system(size: 14, weight: isNext ? .semibold : .medium))
                        .foregroundStyle(
                            isDone
                                ? Design.Colors.secondaryText(for: colorScheme)
                                : Design.Colors.primaryText(for: colorScheme)
                        )
                        .strikethrough(isDone, color: Design.Colors.secondaryText(for: colorScheme))
                        .lineLimit(1)

                    if isNext {
                        Text(item.subtitle)
                            .font(.system(size: 12))
                            .foregroundStyle(Design.Colors.secondaryText(for: colorScheme))
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Spacer(minLength: 4)

                if !isDone {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(
                            isNext
                                ? Design.Colors.primary
                                : Design.Colors.secondaryText(for: colorScheme).opacity(0.5)
                        )
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(
                        isNext
                            ? Design.Colors.primary.opacity(colorScheme == .dark ? 0.10 : 0.06)
                            : Color.clear
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isDone)
        .animation(.spring(response: 0.45, dampingFraction: 0.8), value: isDone)
        .animation(.spring(response: 0.45, dampingFraction: 0.8), value: isNext)
    }

    /// Per-step SF Symbol in a tinted rounded-square chip. The symbol is the
    /// step's own identity icon (folder, safari, widget). State is conveyed
    /// by tint intensity: gray when pending, Apple-blue background + white
    /// icon when current OR done. The row's title strikethrough handles the
    /// "done" semantics.
    private func stepIcon(for item: TutorialManager.ChecklistItem,
                          isDone: Bool,
                          isNext: Bool) -> some View {
        let isActive = isDone || isNext
        return ZStack {
            RoundedRectangle(cornerRadius: 7)
                .fill(
                    isActive
                        ? AnyShapeStyle(Design.Colors.primary)
                        : AnyShapeStyle(
                            Design.Colors.secondaryText(for: colorScheme)
                                .opacity(colorScheme == .dark ? 0.18 : 0.14)
                        )
                )
                .frame(width: 28, height: 28)

            Image(systemName: item.icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(
                    isActive
                        ? .white
                        : Design.Colors.secondaryText(for: colorScheme)
                )
        }
    }

    // MARK: - Shared chrome

    /// The badge mirrors the current task's own identity icon (folder for
    /// "Create a folder", safari for Discover, widget for the feed) rather than
    /// a generic clipboard, so the pill reads as the action it's pointing to.
    /// Falls back to a completion seal once every step is done.
    private var badgeIcon: some View {
        Image(systemName: tutorial.nextItem?.icon ?? "checkmark.seal.fill")
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(Design.Colors.primary)
            .frame(width: 22, height: 22)
            .contentTransition(.symbolEffect(.replace))
    }

    private var currentStepTitle: String {
        tutorial.nextItem?.title ?? "Tour complete"
    }

    private var card: some View {
        RoundedRectangle(cornerRadius: 18)
            // Solid white in light mode so the card matches the white page exactly
            // (regularMaterial reads slightly grey against pure white); ultraThin
            // material in dark for the usual floating-glass look.
            .fill(colorScheme == .dark
                  ? AnyShapeStyle(.ultraThinMaterial)
                  : AnyShapeStyle(Design.Colors.cardBackground(for: colorScheme)))
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(Design.Colors.glassBorder(for: colorScheme), lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.35 : 0.10),
                    radius: 16, y: 5)
    }
}

// MARK: - Device feature detection

enum DeviceFeatures {
    /// True if running on a device whose screen has the Dynamic Island
    /// (iPhone 14 Pro / 15 / 16 / 17 / Air family).
    static let hasDynamicIsland: Bool = {
        #if targetEnvironment(simulator)
        // In Simulator, prefer the device model environment var Xcode sets.
        let name = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] ?? ""
        return identifierLooksDynamicIsland(name)
        #else
        var sysinfo = utsname()
        uname(&sysinfo)
        let identifier = withUnsafePointer(to: &sysinfo.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) { String(validatingUTF8: $0) ?? "" }
        }
        return identifierLooksDynamicIsland(identifier)
        #endif
    }()

    private static func identifierLooksDynamicIsland(_ id: String) -> Bool {
        // iPhone15,2  = iPhone 14 Pro
        // iPhone15,3  = iPhone 14 Pro Max
        // iPhone16,1+ = iPhone 15+
        // iPhone17+   = iPhone 16+
        // iPhone18+   = iPhone 17 + Air
        guard let major = id.split(separator: ",").first?
            .replacingOccurrences(of: "iPhone", with: ""),
              let majorInt = Int(major)
        else { return false }
        if majorInt >= 16 { return true }
        if majorInt == 15 {
            // 15,2 / 15,3 are Pro / Pro Max — both have DI
            // 15,4 / 15,5 are 14 (non-Pro) — no DI
            let parts = id.split(separator: ",")
            if parts.count > 1, let minor = Int(parts[1]) {
                return minor == 2 || minor == 3
            }
            return false
        }
        return false
    }
}
