//
//  MainTabView.swift
//  OpenRSS
//
//  Created by Darius Ehsani on 2/3/26.
//

import SwiftUI

/// Main tab bar container.
///
/// iOS 26+  → Native TabView with Liquid Glass treatment.
/// iOS 17+  → Custom liquid glass sliding pill (Apple News-style).
struct MainTabView: View {

    // MARK: - State

    @State private var selectedTab: AppTab = .today

    // MARK: - Pill Position State (Legacy Custom Tab Bar)

    @State private var pillOffset: CGFloat = 0
    @State private var isDragging: Bool = false
    @State private var pillStretch: CGFloat = 1.0

    // MARK: - Environment

    @Environment(\.colorScheme) private var colorScheme
    @Environment(AppState.self)  private var appState

    // MARK: - Body

    var body: some View {
        if #available(iOS 26.0, *) {
            liquidGlassTabView
        } else {
            legacyCustomTabView
        }
    }

    // MARK: - iOS 26+ Liquid Glass Native TabView

    @available(iOS 26.0, *)
    private var liquidGlassTabView: some View {
        TabView(selection: $selectedTab) {
            Tab("Today", systemImage: Design.Icons.today, value: .today) {
                TodayView()
            }

            Tab("Discover", systemImage: Design.Icons.discover, value: .discover) {
                DiscoverView()
            }

            Tab("My Feeds", systemImage: "list.bullet.below.rectangle", value: .saved) {
                MyFeedsView()
            }

            Tab("Sources", systemImage: Design.Icons.sources, value: .sources) {
                SourcesView()
            }

            Tab("Settings", systemImage: Design.Icons.settings, value: .settings) {
                SettingsView()
            }
        }
        .tabViewStyle(.tabBarOnly)
    }

    // MARK: - Legacy Custom Tab Bar (iOS 17–25)
    // ============================================================================
    // LIQUID GLASS TAB BAR - APPLE NEWS STYLE
    // ============================================================================

    private var legacyCustomTabView: some View {
        ZStack(alignment: .bottom) {
            // Tab content
            Group {
                switch selectedTab {
                case .today:
                    TodayView()
                case .discover:
                    DiscoverView()
                case .saved:
                    MyFeedsView()
                case .sources:
                    SourcesView()
                case .settings:
                    SettingsView()
                }
            }

            // Apple News-style floating tab bar — hidden while reading an article
            appleNewsStyleTabBar
                .offset(y: appState.isReadingArticle ? 140 : 0)
                .opacity(appState.isReadingArticle ? 0 : 1)
                .animation(
                    .spring(response: 0.38, dampingFraction: 0.82),
                    value: appState.isReadingArticle
                )
                .allowsHitTesting(!appState.isReadingArticle)
        }
        .ignoresSafeArea(.keyboard)
    }

    // MARK: - Apple News Style Tab Bar

    private var appleNewsStyleTabBar: some View {
        GeometryReader { geo in
            let totalWidth = geo.size.width
            let tabCount = CGFloat(AppTab.allCases.count)
            let tabWidth = totalWidth / tabCount
            let pillWidth: CGFloat = 56

            ZStack {
                // Glass background
                tabBarBackground

                // THE SLIDING PILL - follows finger directly
                liquidPill(pillWidth: pillWidth)
                    .position(
                        x: pillXPosition(tabWidth: tabWidth, totalWidth: totalWidth, pillWidth: pillWidth),
                        y: 26
                    )
                    // Stretch effect for liquid feel
                    .scaleEffect(x: pillStretch, y: 2.0 - pillStretch, anchor: .center)

                // Tab icons and labels (touchable)
                HStack(spacing: 0) {
                    ForEach(AppTab.allCases, id: \.self) { tab in
                        tabItemView(tab: tab, tabWidth: tabWidth)
                    }
                }
            }
            .frame(height: 70)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if !isDragging {
                            isDragging = true
                            pillOffset = tabCenterX(for: selectedTab, tabWidth: tabWidth)
                        }

                        let fingerX = value.location.x
                        let minX = pillWidth / 2
                        let maxX = totalWidth - pillWidth / 2
                        pillOffset = min(max(fingerX, minX), maxX)

                        let velocity = abs(value.velocity.width)
                        let stretchAmount = min(velocity / 2000, 0.15)
                        withAnimation(.interactiveSpring(response: 0.15, dampingFraction: 0.7)) {
                            pillStretch = 1.0 + stretchAmount
                        }
                    }
                    .onEnded { value in
                        let nearestTabIndex = Int(round((pillOffset - tabWidth / 2) / tabWidth))
                        let clampedIndex = min(max(nearestTabIndex, 0), AppTab.allCases.count - 1)
                        let nearestTab = AppTab.allCases[clampedIndex]

                        withAnimation(.interactiveSpring(response: 0.4, dampingFraction: 0.7)) {
                            selectedTab = nearestTab
                            pillOffset = tabCenterX(for: nearestTab, tabWidth: tabWidth)
                            pillStretch = 1.0
                        }

                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            isDragging = false
                        }
                    }
            )
        }
        .frame(height: 70)
        .padding(.horizontal, 20)
        .padding(.bottom, 24)
    }

    // MARK: - Pill X Position

    private func pillXPosition(tabWidth: CGFloat, totalWidth: CGFloat, pillWidth: CGFloat) -> CGFloat {
        if isDragging {
            return pillOffset
        } else {
            return tabCenterX(for: selectedTab, tabWidth: tabWidth)
        }
    }

    // MARK: - Tab Center X Calculator

    private func tabCenterX(for tab: AppTab, tabWidth: CGFloat) -> CGFloat {
        return CGFloat(tab.index) * tabWidth + tabWidth / 2
    }

    // MARK: - Tab Item View (Icon + Label)

    private func tabItemView(tab: AppTab, tabWidth: CGFloat) -> some View {
        Button {
            withAnimation(.interactiveSpring(response: 0.4, dampingFraction: 0.7)) {
                selectedTab = tab
                pillOffset = tabCenterX(for: tab, tabWidth: tabWidth)
            }
        } label: {
            VStack(spacing: 4) {
                Image(systemName: tab.icon)
                    .font(.system(size: 22, weight: .medium))
                    .symbolVariant(selectedTab == tab ? .fill : .none)
                    .frame(height: 28)

                Text(tab.title)
                    .font(.system(size: 10, weight: selectedTab == tab ? .semibold : .medium))
            }
            .foregroundStyle(
                selectedTab == tab
                    ? Design.Colors.primary
                    : Design.Colors.tabBarInactiveText(for: colorScheme)
            )
            .frame(width: tabWidth, height: 70)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Tab Bar Background (Glass Container)

    private var tabBarBackground: some View {
        Capsule()
            .fill(colorScheme == .dark ? .regularMaterial : .thinMaterial)
            .overlay(
                Capsule()
                    .stroke(
                        LinearGradient(
                            colors: colorScheme == .dark
                                ? [Color.white.opacity(0.3), Color.white.opacity(0.1), Color.white.opacity(0.05)]
                                : [Color.white.opacity(0.9), Color.white.opacity(0.5), Color.black.opacity(0.05)],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 0.5
                    )
            )
            .shadow(
                color: colorScheme == .dark ? .black.opacity(0.4) : .black.opacity(0.15),
                radius: 24,
                y: 8
            )
    }

    // MARK: - Liquid Pill (The Sliding Indicator)

    private func liquidPill(pillWidth: CGFloat) -> some View {
        Capsule()
            .fill(colorScheme == .dark ? .ultraThinMaterial : .regularMaterial)
            .overlay(
                Capsule()
                    .stroke(
                        LinearGradient(
                            colors: colorScheme == .dark
                                ? [Color.white.opacity(0.25), Color.clear]
                                : [Color.white.opacity(0.7), Color.clear],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 0.5
                    )
            )
            .overlay(
                Capsule()
                    .fill(Design.Colors.primary.opacity(colorScheme == .dark ? 0.2 : 0.12))
            )
            .shadow(
                color: Design.Colors.primary.opacity(colorScheme == .dark ? 0.35 : 0.25),
                radius: 10,
                y: 2
            )
            .frame(width: pillWidth, height: 32)
    }
}

// MARK: - AppTab Enum

enum AppTab: CaseIterable {
    case today
    case discover
    case saved
    case sources
    case settings

    var title: String {
        switch self {
        case .today: return "Today"
        case .discover: return "Discover"
        case .saved: return "My Feeds"
        case .sources: return "Sources"
        case .settings: return "Settings"
        }
    }

    var icon: String {
        switch self {
        case .today: return Design.Icons.today
        case .discover: return Design.Icons.discover
        case .saved: return "list.bullet.below.rectangle"
        case .sources: return Design.Icons.sources
        case .settings: return Design.Icons.settings
        }
    }

    var index: Int {
        switch self {
        case .today: return 0
        case .discover: return 1
        case .saved: return 2
        case .sources: return 3
        case .settings: return 4
        }
    }
}

// MARK: - Preview

#Preview {
    MainTabView()
}
