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
        let phase           = tutorial.phase
        let completed       = tutorial.completedItems
        let checklistOpen   = tutorial.checklistExpanded
        let modalActive     = tutorial.coveringModalActive
        let glowTarget      = tutorial.glowTargetItem

        VStack(spacing: 0) {
            if phase == .checklist && !modalActive {
                TutorialChecklistCard(
                    tutorial: tutorial,
                    completedItems: completed,
                    expanded: checklistOpen
                )
                .environment(appState)
                .padding(.horizontal, 12)
                .padding(.top, 6)
                .padding(.bottom, 4)
                .transition(.move(edge: .top).combined(with: .opacity))
            }

            Group {
                if #available(iOS 26.0, *) {
                    liquidGlassTabView
                } else {
                    legacyCustomTabView
                }
            }
        }
        .applyTutorial(
            phase: phase,
            completedItems: completed,
            checklistExpanded: checklistOpen,
            coveringModalActive: modalActive,
            glowTarget: glowTarget,
            tutorial: tutorial,
            appState: appState
        )
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
    /// Attaches the redesigned onboarding flow: hero / intent full-screen
    /// covers, the persistent checklist card, the demo-feed sheet, the
    /// completion celebration, and a global attention glow that highlights
    /// the next action target. Applied per OS branch so the modifier sits on
    /// a concrete view type — this keeps @Observable tracking reliable.
    func applyTutorial(
        phase: TutorialManager.Phase,
        completedItems: Set<TutorialManager.ChecklistItem>,
        checklistExpanded: Bool,
        coveringModalActive: Bool,
        glowTarget: TutorialManager.ChecklistItem?,
        tutorial: TutorialManager,
        appState: AppState
    ) -> some View {
        modifier(TutorialModifier(
            phase: phase,
            completedItems: completedItems,
            checklistExpanded: checklistExpanded,
            coveringModalActive: coveringModalActive,
            glowTarget: glowTarget,
            tutorial: tutorial,
            appState: appState
        ))
    }
}

private struct TutorialModifier: ViewModifier {
    let phase: TutorialManager.Phase
    let completedItems: Set<TutorialManager.ChecklistItem>
    let checklistExpanded: Bool
    let coveringModalActive: Bool
    let glowTarget: TutorialManager.ChecklistItem?
    let tutorial: TutorialManager
    let appState: AppState

    @Environment(\.colorScheme) private var colorScheme

    private var showHero: Binding<Bool> {
        Binding(
            get: { phase == .hero },
            set: { newValue in
                guard !newValue, phase == .hero else { return }
                tutorial.skipHero()
            }
        )
    }

    private var showIntent: Binding<Bool> {
        Binding(
            get: { phase == .intent },
            set: { newValue in
                guard !newValue, phase == .intent else { return }
                tutorial.skipIntent()
            }
        )
    }

    private var showCompletion: Binding<Bool> {
        Binding(
            get: { phase == .completion },
            set: { newValue in
                guard !newValue, phase == .completion else { return }
                tutorial.finishCompletion(appState: appState)
            }
        )
    }

    func body(content: Content) -> some View {
        content
            // Global attention glow — drawn at the top overlay layer so it
            // isn't clipped by clipShape() / toolbar containers further down.
            .overlayPreferenceValue(TutorialGlowKey.self) { prefs in
                if let target = glowTarget, let anchor = prefs[target] {
                    GeometryReader { geo in
                        let frame = geo[anchor]
                        TutorialGlow()
                            .frame(
                                width: max(frame.width, 32) + 36,
                                height: max(frame.height, 32) + 36
                            )
                            .position(x: frame.midX, y: frame.midY)
                            .allowsHitTesting(false)
                    }
                    .ignoresSafeArea()
                    .transition(.opacity)
                }
            }
            // Hero welcome
            .fullScreenCover(isPresented: showHero) {
                TutorialHeroView(
                    onStart: { tutorial.advanceFromHero() },
                    onSkip:  { tutorial.skipHero() }
                )
                .interactiveDismissDisabled()
            }
            // Intent personalization
            .fullScreenCover(isPresented: showIntent) {
                TutorialIntentView(
                    onContinue: { picked in tutorial.completeIntent(picked: picked) },
                    onSkip:     { tutorial.skipIntent() }
                )
                .interactiveDismissDisabled()
            }
            // Completion celebration
            .fullScreenCover(isPresented: showCompletion) {
                TutorialCompletionView(
                    onFinish: { tutorial.finishCompletion(appState: appState) }
                )
                .interactiveDismissDisabled()
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
