//
//  SourceAffinityView.swift
//  OpenRSS
//
//  Phase 2d — Per-source affinity panel.
//  Shows affinity tier labels and provides reset controls.
//  All affinity data is on-device only. No sync. No external analytics.
//

import SwiftUI

// MARK: - SourceAffinityView

struct SourceAffinityView: View {

    // MARK: - State

    @State private var records: [SourceAffinityRecord] = []
    @State private var showResetAllConfirmation = false

    // MARK: - Environment

    @Environment(\.colorScheme) private var colorScheme

    // MARK: - Dependencies

    private let store = SQLiteStore.shared
    private let dataService: FeedDataService = SwiftDataService.shared

    // MARK: - Body

    var body: some View {
        ScrollView {
            VStack(spacing: Design.Spacing.section) {
                headerDescription
                sourcesList
                resetAllSection
            }
            .padding(.top, Design.Spacing.edge)
        }
        .background(Design.Colors.background(for: colorScheme))
        .navigationTitle("Reading Signals")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { loadRecords() }
        .confirmationDialog(
            "Reset All Reading Signals",
            isPresented: $showResetAllConfirmation,
            titleVisibility: .visible
        ) {
            Button("Reset All", role: .destructive) {
                resetAll()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This will clear all affinity scores and interaction history. This cannot be undone.")
        }
    }

    // MARK: - Header Description

    private var headerDescription: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.small) {
            HStack(spacing: 8) {
                Image(systemName: "waveform.path.ecg")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Design.Colors.primary)

                Text("READING SIGNALS")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Design.Colors.secondaryText(for: colorScheme))
                    .tracking(0.5)
            }

            Text("OpenRSS learns from your reading habits to surface articles you care about. All data stays on your device.")
                .font(.system(size: 14))
                .foregroundStyle(Design.Colors.secondaryText(for: colorScheme))
                .lineSpacing(2)
        }
        .padding(.horizontal, Design.Spacing.edge)
    }

    // MARK: - Sources List

    private var sourcesList: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.small) {
            HStack(spacing: 8) {
                Image(systemName: "list.bullet")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Design.Colors.primary)

                Text("PER-SOURCE AFFINITY")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Design.Colors.secondaryText(for: colorScheme))
                    .tracking(0.5)
            }
            .padding(.horizontal, Design.Spacing.edge)

            if records.isEmpty {
                emptyState
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(records.enumerated()), id: \.element.sourceID) { index, record in
                        sourceRow(for: record)

                        if index < records.count - 1 {
                            Rectangle()
                                .fill(Design.Colors.subtleBorder)
                                .frame(height: 1)
                                .padding(.leading, Design.Spacing.edge)
                        }
                    }
                }
                .background(Design.Colors.cardBackground(for: colorScheme))
                .clipShape(RoundedRectangle(cornerRadius: Design.Radius.standard))
                .overlay(
                    RoundedRectangle(cornerRadius: Design.Radius.standard)
                        .stroke(
                            colorScheme == .dark
                                ? Design.Colors.subtleBorder
                                : Color.black.opacity(0.08),
                            lineWidth: 1
                        )
                )
                .padding(.horizontal, Design.Spacing.edge)
            }
        }
    }

    // MARK: - Source Row

    /// Resolves a human-readable source name from FeedDataService, falling
    /// back to a truncated UUID when the source is no longer subscribed.
    private func sourceName(for sourceID: UUID) -> String {
        dataService.source(for: sourceID)?.name
            ?? (sourceID.uuidString.prefix(8) + "...")
    }

    private func sourceRow(for record: SourceAffinityRecord) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(sourceName(for: record.sourceID))
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Design.Colors.primaryText(for: colorScheme))

                HStack(spacing: 8) {
                    affinityBadge(for: record)

                    Text("\(record.eventCount) events")
                        .font(.system(size: 12))
                        .foregroundStyle(Design.Colors.secondaryText(for: colorScheme))
                }
            }

            Spacer()

            Button {
                resetAffinity(for: record.sourceID)
            } label: {
                Text("Reset")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Design.Colors.primary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: Design.Radius.small)
                            .fill(Design.Colors.primary.opacity(colorScheme == .dark ? 0.1 : 0.08))
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, Design.Spacing.edge)
        .padding(.vertical, 12)
    }

    // MARK: - Affinity Badge

    private func affinityBadge(for record: SourceAffinityRecord) -> some View {
        let label = record.affinityLabel
        let color = affinityColor(for: record.affinityScore)

        return HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)

            Text(label)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(color)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(color.opacity(0.12))
        )
    }

    private func affinityColor(for score: Double) -> Color {
        switch score {
        case ..<0:       return .red
        case 0..<0.3:    return Design.Colors.secondaryText(for: colorScheme)
        case 0.3..<0.7:  return .orange
        default:         return .green
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: Design.Spacing.small) {
            Image(systemName: "chart.bar")
                .font(.system(size: 32, weight: .ultraLight))
                .foregroundStyle(Design.Colors.secondaryText(for: colorScheme).opacity(0.5))

            Text("No reading signals yet")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Design.Colors.secondaryText(for: colorScheme))

            Text("Start reading articles and OpenRSS will learn your preferences.")
                .font(.system(size: 13))
                .foregroundStyle(Design.Colors.secondaryText(for: colorScheme).opacity(0.7))
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, 32)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, Design.Spacing.edge)
    }

    // MARK: - Reset All Section

    private var resetAllSection: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.small) {
            HStack(spacing: 8) {
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Design.Colors.primary)

                Text("DATA MANAGEMENT")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Design.Colors.secondaryText(for: colorScheme))
                    .tracking(0.5)
            }
            .padding(.horizontal, Design.Spacing.edge)

            Button {
                showResetAllConfirmation = true
            } label: {
                HStack {
                    Text("Reset all reading signals")
                        .font(.system(size: 16))
                        .foregroundStyle(.red)

                    Spacer()

                    Image(systemName: "trash")
                        .font(.system(size: 14))
                        .foregroundStyle(.red.opacity(0.6))
                }
                .padding(.horizontal, Design.Spacing.edge)
                .padding(.vertical, 14)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .background(Design.Colors.cardBackground(for: colorScheme))
            .clipShape(RoundedRectangle(cornerRadius: Design.Radius.standard))
            .overlay(
                RoundedRectangle(cornerRadius: Design.Radius.standard)
                    .stroke(
                        colorScheme == .dark
                            ? Design.Colors.subtleBorder
                            : Color.black.opacity(0.08),
                        lineWidth: 1
                    )
            )
            .padding(.horizontal, Design.Spacing.edge)

            Text("Clears all affinity scores and interaction events. Your subscriptions and settings are not affected.")
                .font(.system(size: 12))
                .foregroundStyle(Design.Colors.secondaryText(for: colorScheme).opacity(0.6))
                .padding(.horizontal, Design.Spacing.edge)
        }
    }

    // MARK: - Actions

    private func loadRecords() {
        records = store.fetchAllAffinities()
    }

    private func resetAffinity(for sourceID: UUID) {
        store.resetAffinity(forSource: sourceID)
        loadRecords()
    }

    private func resetAll() {
        store.resetAllAffinityData()
        loadRecords()
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        SourceAffinityView()
    }
}
