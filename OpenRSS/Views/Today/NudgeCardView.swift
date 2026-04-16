//
//  NudgeCardView.swift
//  OpenRSS
//
//  Phase 2c — Warning card shown when a source is flooding the feed.
//  Displays the source name, a warning message, and options to
//  adjust the source's slot limit or mute temporarily.
//

import SwiftUI

// MARK: - NudgeCardView

struct NudgeCardView: View {

    // MARK: - Properties

    let nudge: NudgeCard
    let source: Source?
    var onAdjustSlotLimit: (() -> Void)?
    var onMuteTemporarily: (() -> Void)?

    // MARK: - State

    @State private var isDismissed = false

    // MARK: - Environment

    @Environment(\.colorScheme) private var colorScheme

    // MARK: - Body

    var body: some View {
        if !isDismissed {
            VStack(alignment: .leading, spacing: Design.Spacing.small) {
                warningHeader
                warningMessage
                actionButtons
            }
            .padding(Design.Spacing.cardPadding)
            .background(warningBackground)
            .clipShape(RoundedRectangle(cornerRadius: Design.Radius.standard))
            .overlay(
                RoundedRectangle(cornerRadius: Design.Radius.standard)
                    .stroke(warningBorderColor, lineWidth: 1)
            )
            .shadow(
                color: warningShadowColor,
                radius: colorScheme == .dark ? 16 : 12,
                x: 0,
                y: colorScheme == .dark ? 8 : 4
            )
        }
    }

    // MARK: - Subviews

    private var warningHeader: some View {
        HStack(spacing: 8) {
            // Warning icon
            ZStack {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.orange.opacity(0.2))
                    .frame(width: 24, height: 24)

                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.orange)
            }

            // Source name
            Text(source?.name ?? nudge.sourceName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Design.Colors.primaryText(for: colorScheme))

            Spacer()

            // Dismiss button
            Button {
                withAnimation(Design.Animation.quick) {
                    isDismissed = true
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Design.Colors.secondaryText(for: colorScheme))
                    .frame(width: 28, height: 28)
                    .background(
                        Circle()
                            .fill(Design.Colors.secondaryText(for: colorScheme).opacity(0.1))
                    )
            }
            .buttonStyle(.plain)
        }
    }

    private var warningMessage: some View {
        Text(nudge.message)
            .font(Design.Typography.body)
            .foregroundStyle(Design.Colors.secondaryText(for: colorScheme))
            .lineLimit(2)
    }

    private var actionButtons: some View {
        HStack(spacing: 10) {
            // Adjust slot limit button
            Button {
                onAdjustSlotLimit?()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 11, weight: .semibold))
                    Text("Adjust limit")
                        .font(.system(size: 13, weight: .semibold))
                }
                .foregroundStyle(Design.Colors.primary)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .fill(Design.Colors.primary.opacity(colorScheme == .dark ? 0.15 : 0.1))
                )
            }
            .buttonStyle(.plain)

            // Mute temporarily button
            Button {
                onMuteTemporarily?()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "bell.slash.fill")
                        .font(.system(size: 11, weight: .semibold))
                    Text("Mute 24h")
                        .font(.system(size: 13, weight: .semibold))
                }
                .foregroundStyle(Design.Colors.secondaryText(for: colorScheme))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .fill(Design.Colors.secondaryText(for: colorScheme).opacity(0.1))
                )
            }
            .buttonStyle(.plain)

            Spacer()
        }
        .padding(.top, Design.Spacing.xSmall)
    }

    // MARK: - Warning Styling

    private var warningBackground: some View {
        colorScheme == .dark
            ? Color(hex: "1c1a14")   // warm dark tint
            : Color(hex: "fff8f0")   // warm light tint
    }

    private var warningBorderColor: Color {
        colorScheme == .dark
            ? Color.orange.opacity(0.2)
            : Color.orange.opacity(0.15)
    }

    private var warningShadowColor: Color {
        colorScheme == .dark
            ? Color.orange.opacity(0.1)
            : Color.orange.opacity(0.08)
    }
}
