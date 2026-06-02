//
//  PayamTutorialWidgetLiveActivity.swift
//  PayamTutorialWidget
//
//  Dynamic Island + Lock Screen presentation for the Payam onboarding tour.
//
//  Layouts:
//    Compact leading:  lanyardcard.fill (Apple blue)
//    Compact trailing: row of N dots — completed = filled green, pending = dashed outline
//    Minimal:          lanyardcard.fill
//    Expanded:         current step title + count + large dots row
//    Lock-screen:      lanyard badge + step title + dots + count
//

import ActivityKit
import SwiftUI
import WidgetKit

@available(iOS 16.2, *)
struct PayamTutorialWidgetLiveActivity: Widget {

    private static let appleBlue = Color(red: 0/255, green: 113/255, blue: 227/255) // #0071E3
    private static let pillGreen = Color.green

    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TutorialActivityAttributes.self) { context in
            // Lock-Screen / Banner presentation
            lockScreenView(state: context.state)
                .padding(16)
                .activityBackgroundTint(Color.black.opacity(0.85))
                .activitySystemActionForegroundColor(.white)

        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: "lanyardcard.fill")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(Self.appleBlue)
                        .padding(.leading, 6)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text("\(context.state.completedCount) / \(context.state.totalCount)")
                        .font(.system(size: 14, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .padding(.trailing, 6)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.state.currentStepTitle)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    dotsRow(state: context.state, size: 14, spacing: 10)
                        .padding(.top, 6)
                        .padding(.bottom, 4)
                        .frame(maxWidth: .infinity)
                }
            } compactLeading: {
                Image(systemName: "lanyardcard.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Self.appleBlue)
            } compactTrailing: {
                dotsRow(state: context.state, size: 6, spacing: 3)
                    .padding(.trailing, 2)
            } minimal: {
                Image(systemName: "lanyardcard.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Self.appleBlue)
            }
            .keylineTint(Self.appleBlue)
        }
    }

    // MARK: - Lock-screen layout

    @ViewBuilder
    private func lockScreenView(state: TutorialActivityAttributes.ContentState) -> some View {
        HStack(spacing: 14) {
            Image(systemName: "lanyardcard.fill")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(Self.appleBlue)
                .frame(width: 40, height: 40)
                .background(Circle().fill(Self.appleBlue.opacity(0.18)))

            VStack(alignment: .leading, spacing: 6) {
                Text("Payam Tour")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.7))
                    .tracking(0.6)
                    .textCase(.uppercase)

                Text(state.currentStepTitle)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                dotsRow(state: state, size: 8, spacing: 5)
            }

            Spacer(minLength: 0)

            Text("\(state.completedCount) / \(state.totalCount)")
                .font(.system(size: 14, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.85))
        }
    }

    // MARK: - Dots row

    @ViewBuilder
    private func dotsRow(
        state: TutorialActivityAttributes.ContentState,
        size: CGFloat,
        spacing: CGFloat
    ) -> some View {
        HStack(spacing: spacing) {
            ForEach(state.stepIDs, id: \.self) { id in
                let isDone = state.completedIDs.contains(id)
                Circle()
                    .fill(isDone ? AnyShapeStyle(Self.pillGreen) : AnyShapeStyle(Color.clear))
                    .overlay(
                        Circle()
                            .stroke(
                                isDone ? Self.pillGreen : Color.white.opacity(0.55),
                                style: StrokeStyle(
                                    lineWidth: max(1, size / 6),
                                    dash: isDone ? [] : [size / 3, size / 4]
                                )
                            )
                    )
                    .frame(width: size, height: size)
            }
        }
    }
}

// MARK: - Preview

@available(iOS 16.2, *)
#Preview(
    "Tutorial DI",
    as: .dynamicIsland(.expanded),
    using: TutorialActivityAttributes()
) {
    PayamTutorialWidgetLiveActivity()
} contentStates: {
    TutorialActivityAttributes.ContentState(
        stepIDs: ["create_folder", "subscribe_first", "read_today"],
        completedIDs: ["create_folder"],
        currentStepTitle: "Select a feed from Discover"
    )
    TutorialActivityAttributes.ContentState(
        stepIDs: ["create_folder", "subscribe_first", "read_today"],
        completedIDs: ["create_folder", "subscribe_first"],
        currentStepTitle: "Read your feed"
    )
}
