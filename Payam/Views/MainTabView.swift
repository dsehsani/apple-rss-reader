//
//  MainTabView.swift
//  Payam
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

    @State private var searchText: String = ""

    // MARK: - Namespace for matched geometry tab highlight

    @Namespace private var tabNamespace

    // MARK: - Tutorial

    private var tutorial: TutorialManager { .shared }

    // MARK: - Environment

    @Environment(\.colorScheme) private var colorScheme
    @Environment(AppState.self)  private var appState

    // MARK: - Body

    var body: some View {
        // Read tutorial state here in body so @Observable registers these as
        // dependencies on MainTabView — guaranteeing a re-render when they change.
        let isActive = tutorial.isActive
        let step     = tutorial.currentStep

        if #available(iOS 26.0, *) {
            liquidGlassTabView
                .applyTutorial(isActive: isActive, step: step, tutorial: tutorial, appState: appState)
        } else {
            legacyCustomTabView
                .applyTutorial(isActive: isActive, step: step, tutorial: tutorial, appState: appState)
        }
    }

    // MARK: - iOS 26+ Liquid Glass Native TabView

    @available(iOS 26.0, *)
    private var liquidGlassTabView: some View {
        TabView(selection: Bindable(appState).selectedTab) {
            Tab("Feed", systemImage: Design.Icons.today, value: .today) {
                TodayView()
            }

            Tab("Discover", systemImage: Design.Icons.discover, value: .discover) {
                DiscoverView()
            }

            Tab("Sources", systemImage: "antenna.radiowaves.left.and.right", value: .saved) {
                MyFeedsView()
            }

            Tab("Settings", systemImage: Design.Icons.settings, value: .settings) {
                SettingsView()
            }

            Tab(value: .search, role: .search) {
                NavigationStack {
                    SearchView(searchText: $searchText)
                        .navigationTitle("Search")
                }
                .searchable(text: $searchText, prompt: "Search articles")
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
                switch appState.selectedTab {
                case .today:
                    TodayView()
                case .discover:
                    DiscoverView()
                case .saved:
                    MyFeedsView()
                case .settings:
                    SettingsView()
                case .search:
                    EmptyView()
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

    // MARK: - Tab Bar

    private var appleNewsStyleTabBar: some View {
        HStack(spacing: 0) {
            ForEach(AppTab.legacyTabs, id: \.self) { tab in
                tabButton(tab)
            }
        }
        .frame(height: 64)
        .padding(.horizontal, 8)
        .background(tabBarBackground)
        .padding(.horizontal, 20)
        .padding(.bottom, 24)
    }

    // MARK: - Tab Button

    private func tabButton(_ tab: AppTab) -> some View {
        let isSelected = appState.selectedTab == tab

        return Button {
            withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
                appState.selectedTab = tab
            }
        } label: {
            ZStack {
                // Sliding selection background — moves via matchedGeometryEffect
                if isSelected {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Design.Colors.primary.opacity(colorScheme == .dark ? 0.18 : 0.11))
                        .matchedGeometryEffect(id: "tabHighlight", in: tabNamespace)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 6)
                }

                VStack(spacing: 3) {
                    Image(systemName: tab.icon)
                        .font(.system(size: 21, weight: isSelected ? .semibold : .regular))
                        .symbolVariant(isSelected ? .fill : .none)
                        .frame(height: 26)
                        .scaleEffect(isSelected ? 1.05 : 1.0)
                        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)

                    Text(tab.title)
                        .font(.system(size: 10, weight: isSelected ? .semibold : .medium))
                }
                .foregroundStyle(
                    isSelected
                        ? Design.Colors.primary
                        : Design.Colors.tabBarInactiveText(for: colorScheme)
                )
                .animation(.easeInOut(duration: 0.18), value: isSelected)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 64)
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
                color: colorScheme == .dark ? .black.opacity(0.5) : .black.opacity(0.08),
                radius: colorScheme == .dark ? 24 : 16,
                y: colorScheme == .dark ? 8 : 4
            )
    }
}

// MARK: - Tutorial Overlay Modifier

private extension View {
    /// Attaches the tutorial overlay, tab-switching, and start-on-appear logic.
    /// Applied to each OS branch individually so the modifier sits on a concrete
    /// view type, not a Group — this keeps @Observable tracking reliable.
    func applyTutorial(
        isActive: Bool,
        step: TutorialStep,
        tutorial: TutorialManager,
        appState: AppState
    ) -> some View {
        self
            .overlayPreferenceValue(TutorialSpotlightKey.self) { prefs in
                // `isActive` and `step` are captured from body's local lets,
                // so this closure always reflects the latest tracked values.
                if isActive {
                    GeometryReader { geo in
                        let frame: CGRect? = prefs[step].map { geo[$0] }
                        TutorialOverlayView(
                            step: step,
                            spotlightFrame: frame,
                            screenSize: geo.size,
                            onNext: { tutorial.advance() },
                            onSkip: { tutorial.finish() }
                        )
                    }
                    .ignoresSafeArea()
                }
            }
            .onChange(of: step) { _, newStep in
                if let tab = newStep.targetTab {
                    withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
                        appState.selectedTab = tab
                    }
                }
            }
            .onAppear {
                tutorial.startIfNeeded()
            }
    }
}

// MARK: - AppTab Enum

enum AppTab: CaseIterable {
    case today
    case discover
    case saved
    case settings
    case search

    /// Tabs shown in the legacy custom tab bar (search is handled natively on iOS 26+)
    static var legacyTabs: [AppTab] { [.today, .discover, .saved, .settings] }

    var title: String {
        switch self {
        case .today: return "Feed"
        case .discover: return "Discover"
        case .saved: return "Sources"
        case .settings: return "Settings"
        case .search: return "Search"
        }
    }

    var icon: String {
        switch self {
        case .today: return Design.Icons.today
        case .discover: return Design.Icons.discover
        case .saved: return "antenna.radiowaves.left.and.right"
        case .settings: return Design.Icons.settings
        case .search: return Design.Icons.search
        }
    }

    var index: Int {
        switch self {
        case .today: return 0
        case .discover: return 1
        case .saved: return 2
        case .settings: return 3
        case .search: return 4
        }
    }
}

// MARK: - Preview

#Preview {
    MainTabView()
}
