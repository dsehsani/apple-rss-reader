//
//  FilterRuleCardView.swift
//  Payam
//
//  Renders the `rule_card` agent view: a single proposed FilterRule with a
//  one-tap Save button that persists a FilterRuleModel into SwiftData.
//
//  Once saved, the same rule will apply on the next river snapshot rebuild
//  (FilterRuleService is wired into RiverSnapshotService.assembleSnapshot).
//

import SwiftUI
import SwiftData

// MARK: - FilterRuleCardView

struct FilterRuleCardView: View {

    let payload: FilterRuleCard

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.modelContext) private var modelContext

    @State private var saveState: SaveState = .idle

    private enum SaveState: Equatable {
        case idle
        case saving
        case saved
        case failed(String)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            VStack(alignment: .leading, spacing: 8) {
                Text(payload.displayText)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Design.Colors.primaryText(for: colorScheme))

                if !payload.rationale.isEmpty {
                    Text(payload.rationale)
                        .font(.system(size: 13))
                        .foregroundStyle(Design.Colors.secondaryText(for: colorScheme))
                        .fixedSize(horizontal: false, vertical: true)
                }

                predicateChips
                    .padding(.top, 4)

                if scopeLabel != "Everywhere" {
                    HStack(spacing: 6) {
                        Image(systemName: "scope")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Design.Colors.secondaryText(for: colorScheme))
                        Text(scopeLabel)
                            .font(.system(size: 12))
                            .foregroundStyle(Design.Colors.secondaryText(for: colorScheme))
                    }
                    .padding(.top, 2)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 14)
                    .fill(Design.Colors.cardBackground(for: colorScheme))
                    .overlay {
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(Design.Colors.glassBorder(for: colorScheme), lineWidth: 0.5)
                    }
            }

            actionRow
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "line.3.horizontal.decrease.circle")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Design.Colors.primary)
            Text("Proposed filter rule")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Design.Colors.secondaryText(for: colorScheme))
                .textCase(.uppercase)
                .tracking(0.6)
        }
    }

    // MARK: - Predicate chips

    private var predicateChips: some View {
        FlowingChips(chips: buildChips())
    }

    private func buildChips() -> [ChipModel] {
        var chips: [ChipModel] = []
        for kind in payload.predicate.contentKinds {
            chips.append(ChipModel(label: kind.replacingOccurrences(of: "_", with: " "), icon: "tag.fill"))
        }
        for kw in payload.predicate.keywords {
            chips.append(ChipModel(label: kw, icon: "textformat"))
        }
        for ph in payload.predicate.phrases {
            chips.append(ChipModel(label: "\u{201C}\(ph)\u{201D}", icon: "text.quote"))
        }
        for url in payload.predicate.sourceFeedURLs {
            chips.append(ChipModel(label: hostForURL(url) ?? url, icon: "antenna.radiowaves.left.and.right"))
        }
        return chips
    }

    // MARK: - Action row

    private var actionRow: some View {
        HStack(spacing: 10) {
            switch saveState {
            case .idle:
                Button {
                    Task { await save() }
                } label: {
                    Label("Save rule", systemImage: "checkmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Design.Colors.primary, in: Capsule())
                }
                .buttonStyle(.plain)

                Text("Apply next refresh")
                    .font(.system(size: 12))
                    .foregroundStyle(Design.Colors.secondaryText(for: colorScheme))

            case .saving:
                ProgressView().controlSize(.small)
                Text("Saving…")
                    .font(.system(size: 12))
                    .foregroundStyle(Design.Colors.secondaryText(for: colorScheme))

            case .saved:
                Label("Saved — rule is active", systemImage: "checkmark.seal.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.green)

            case .failed(let msg):
                Label(msg, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.orange)
            }

            Spacer()
        }
    }

    // MARK: - Save

    @MainActor
    private func save() async {
        saveState = .saving

        let predicate = FilterPredicate(
            keywords:       payload.predicate.keywords,
            phrases:        payload.predicate.phrases,
            sourceFeedURLs: payload.predicate.sourceFeedURLs,
            contentKinds:   payload.predicate.contentKinds
        )

        let rule = FilterRuleModel(
            displayText: payload.displayText,
            predicate:   predicate,
            scope:       FilterScope(raw: payload.scope),
            rationale:   payload.rationale,
            sourceText:  payload.sourceText,
            createdBy:   "agent"
        )

        modelContext.insert(rule)

        do {
            try modelContext.save()
            saveState = .saved
        } catch {
            saveState = .failed("Couldn't save")
        }
    }

    // MARK: - Helpers

    private var scopeLabel: String {
        switch FilterScope(raw: payload.scope) {
        case .global:                return "Everywhere"
        case .folder(let name):      return "In folder: \(name)"
        case .feed(let url):         return "In feed: \(hostForURL(url) ?? url)"
        }
    }

    private func hostForURL(_ url: String) -> String? {
        URL(string: url)?.host
    }
}

// MARK: - Chip primitives

private struct ChipModel: Identifiable {
    var id: String { label + icon }
    let label: String
    let icon: String
}

private struct FlowingChips: View {
    let chips: [ChipModel]
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        if chips.isEmpty {
            EmptyView()
        } else {
            // Wrapping HStack via flexible-width LazyVGrid with a single adaptive column.
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 110, maximum: 240), spacing: 6, alignment: .leading)],
                alignment: .leading,
                spacing: 6
            ) {
                ForEach(chips) { c in
                    HStack(spacing: 6) {
                        Image(systemName: c.icon)
                            .font(.system(size: 10, weight: .semibold))
                        Text(c.label)
                            .font(.system(size: 12, weight: .medium))
                            .lineLimit(1)
                    }
                    .foregroundStyle(Design.Colors.primary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Design.Colors.primary.opacity(0.10), in: Capsule())
                }
            }
        }
    }
}
