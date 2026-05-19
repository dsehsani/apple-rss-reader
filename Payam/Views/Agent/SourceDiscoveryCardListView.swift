//
//  SourceDiscoveryCardListView.swift
//  Payam
//
//  Renders the `card_list` agent view: a vertically stacked list of suggested
//  RSS feeds, each with a one-tap Add button. Tap → opens the folder picker
//  sheet (AddFeedView pre-filled with the feed URL and name) so the user
//  chooses where it lands, consistent with the manual add-feed flow.
//
//  The card retains per-card state (.idle / .added / .failed) so the
//  list reflects the result of each independent action.
//

import SwiftUI

// MARK: - SourceDiscoveryCardListView

struct SourceDiscoveryCardListView: View {

    let payload: SourceDiscoveryCardList

    @Environment(\.colorScheme) private var colorScheme
    @State private var states: [String: AddState] = [:]
    @State private var pendingCard: SourceDiscoveryCardList.Card?

    private enum AddState: Equatable {
        case idle
        case adding
        case added
        case failed(String)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            if payload.cards.isEmpty {
                emptyState
            } else {
                ForEach(payload.cards) { card in
                    cardRow(card)
                }
            }
        }
        .sheet(item: $pendingCard, onDismiss: refreshAddedStates) { card in
            AddFeedView(prefill: (feedURL: card.feedURL, title: card.name))
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Design.Colors.primary)
            Text("Feeds about \(payload.topic)")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Design.Colors.secondaryText(for: colorScheme))
                .textCase(.uppercase)
                .tracking(0.6)
        }
    }

    // MARK: - Empty

    private var emptyState: some View {
        Text(payload.emptyReason ?? "No matches in the catalog. Try a broader topic.")
            .font(.system(size: 14))
            .foregroundStyle(Design.Colors.secondaryText(for: colorScheme))
            .padding(.vertical, 8)
    }

    // MARK: - Card row

    @ViewBuilder
    private func cardRow(_ card: SourceDiscoveryCardList.Card) -> some View {
        let state = states[card.feedURL] ?? .idle

        HStack(alignment: .top, spacing: 12) {
            // Leading icon chip
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Design.Colors.primary.opacity(card.alreadySubscribed ? 0.06 : 0.14))
                    .frame(width: 40, height: 40)
                Image(systemName: card.alreadySubscribed ? "checkmark" : "dot.radiowaves.left.and.right")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(card.alreadySubscribed
                                     ? Design.Colors.secondaryText(for: colorScheme)
                                     : Design.Colors.primary)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(card.name)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Design.Colors.primaryText(for: colorScheme))
                    .opacity(card.alreadySubscribed ? 0.6 : 1.0)

                Text(card.oneLine)
                    .font(.system(size: 13))
                    .foregroundStyle(Design.Colors.secondaryText(for: colorScheme))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                if let why = card.why, !why.isEmpty {
                    Text(why)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Design.Colors.primary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 8)

            actionButton(for: card, state: state)
                .padding(.top, 2)
        }
        .padding(12)
        .background {
            RoundedRectangle(cornerRadius: 14)
                .fill(Design.Colors.cardBackground(for: colorScheme))
                .overlay {
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Design.Colors.glassBorder(for: colorScheme), lineWidth: 0.5)
                }
        }
    }

    // MARK: - Action button

    @ViewBuilder
    private func actionButton(for card: SourceDiscoveryCardList.Card, state: AddState) -> some View {
        switch state {
        case .idle:
            if card.alreadySubscribed {
                Label("Added", systemImage: "checkmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Design.Colors.secondaryText(for: colorScheme))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
            } else {
                Button {
                    pendingCard = card
                } label: {
                    Label("Add", systemImage: "plus")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Design.Colors.primary, in: Capsule())
                }
                .buttonStyle(.plain)
            }
        case .adding:
            ProgressView()
                .controlSize(.small)
                .frame(width: 60, height: 28)
        case .added:
            Label("Added", systemImage: "checkmark")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.green)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
        case .failed(let msg):
            Text(msg)
                .font(.system(size: 11))
                .foregroundStyle(.orange)
                .lineLimit(2)
        }
    }

    // MARK: - Sheet dismiss

    @MainActor
    private func refreshAddedStates() {
        let subscribedURLs = Set(SwiftDataService.shared.sources.map { $0.feedURL.lowercased() })
        for card in payload.cards {
            if subscribedURLs.contains(card.feedURL.lowercased()) {
                states[card.feedURL] = .added
            }
        }
    }
}
