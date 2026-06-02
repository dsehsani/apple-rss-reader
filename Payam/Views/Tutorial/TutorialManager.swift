//
//  TutorialManager.swift
//  Payam
//
//  @Observable singleton driving the first-run onboarding tour.
//
//  Flow:
//    hero    → welcome cover
//    intent  → interest picker (seeds Discover ordering)
//    checklist → persistent collapsible card with 5 items; user completes them
//                by performing real actions (subscribe, read, create folder, etc.)
//    completion → celebration cover; tap "Start reading" to finish
//

import SwiftUI

// MARK: - Notifications

extension Notification.Name {
    /// Posted by TodayView when the user opens an article.
    static let articleOpened = Notification.Name("payam.articleOpened")
}

// MARK: - TutorialManager

@Observable
final class TutorialManager {

    // MARK: - Phase

    enum Phase: Equatable {
        case dismissed   // not running
        case hero        // full-screen welcome
        case intent      // interest picker
        case checklist   // persistent top card
        case completion  // celebration
    }

    // MARK: - Checklist Item

    /// Three core actions that capture the essence of the RSS reader.
    /// Order matters: it controls the order rows render and the order DI
    /// dots appear left-to-right.
    enum ChecklistItem: String, CaseIterable, Identifiable {
        case createFolder    = "create_folder"
        case subscribeFirst  = "subscribe_first"
        case readToday       = "read_today"

        var id: String { rawValue }

        var title: String {
            switch self {
            case .createFolder:   return "Create a folder"
            case .subscribeFirst: return "Select a feed from Discover"
            case .readToday:      return "Read your feed"
            }
        }

        var subtitle: String {
            switch self {
            case .createFolder:   return "Use the + menu in Sources to make a folder."
            case .subscribeFirst: return "Tap + on a recommended feed in Discover."
            case .readToday:      return "Tap any article in your river to open it."
            }
        }

        /// Icons mirror each step's destination so the row reads as the place it
        /// sends you: folder for "Create a folder" (Sources), the Discover tab
        /// glyph for "Select a feed from Discover", the Feed tab glyph for "Read
        /// your feed".
        var icon: String {
            switch self {
            case .createFolder:   return "folder.fill"
            case .subscribeFirst: return Design.Icons.discover   // sparkles
            case .readToday:      return Design.Icons.today      // newspaper.fill
            }
        }

        var targetTab: AppTab? {
            switch self {
            case .createFolder:   return .saved
            case .subscribeFirst: return .discover
            case .readToday:      return .today
            }
        }
    }

    // MARK: - Singleton

    static let shared = TutorialManager()

    // MARK: - Persistence keys

    private static let completedKey = "payam.tutorial.completed"
    private static let interestsKey = "payam.tutorial.interests"
    private static func itemKey(_ item: ChecklistItem) -> String {
        "payam.tutorial.checklist.\(item.rawValue)"
    }

    // MARK: - Observable state

    var phase: Phase = .dismissed
    var interests: Set<String> = []
    var completedItems: Set<ChecklistItem> = []
    var checklistExpanded: Bool = true

    /// While true the persistent checklist hides itself (a sheet/modal would cover it).
    var coveringModalActive: Bool = false

    /// Which element should pulse with the attention glow right now. Nil = none.
    var glowTargetItem: ChecklistItem? = nil

    // MARK: - Derived state

    var isActive: Bool { phase != .dismissed }

    var progress: (done: Int, total: Int) {
        (completedItems.count, ChecklistItem.allCases.count)
    }

    var nextItem: ChecklistItem? {
        ChecklistItem.allCases.first { !completedItems.contains($0) }
    }

    var isChecklistVisible: Bool {
        phase == .checklist && !coveringModalActive
    }

    // MARK: - Lifecycle

    private var observers: [NSObjectProtocol] = []

    private init() {
        loadInterests()
        loadCompletedItems()
    }

    /// Called on app launch. Starts the tour only on first run.
    func startIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: Self.completedKey) else { return }
        start()
    }

    /// Replay path — wipes prior progress and restarts at hero.
    func start() {
        completedItems = []
        interests = []
        UserDefaults.standard.removeObject(forKey: Self.completedKey)
        UserDefaults.standard.removeObject(forKey: Self.interestsKey)
        for item in ChecklistItem.allCases {
            UserDefaults.standard.removeObject(forKey: Self.itemKey(item))
        }
        glowTargetItem = nil
        checklistExpanded = true
        withAnimation(.spring(response: 0.42, dampingFraction: 0.85)) {
            phase = .hero
        }
        observeDataEvents()
    }

    // MARK: - Hero / Intent transitions

    func advanceFromHero() {
        withAnimation(.spring(response: 0.42, dampingFraction: 0.85)) {
            phase = .intent
        }
    }

    func skipHero() {
        finish()
    }

    func completeIntent(picked: Set<String>) {
        interests = picked
        saveInterests()
        checklistExpanded = true
        withAnimation(.spring(response: 0.42, dampingFraction: 0.85)) {
            phase = .checklist
        }
        TutorialLiveActivityController.shared.start(
            completed: completedItems,
            currentTitle: nextItem?.title ?? "All done"
        )
    }

    func skipIntent() {
        checklistExpanded = true
        withAnimation(.spring(response: 0.42, dampingFraction: 0.85)) {
            phase = .checklist
        }
        TutorialLiveActivityController.shared.start(
            completed: completedItems,
            currentTitle: nextItem?.title ?? "All done"
        )
    }

    // MARK: - Checklist interaction

    /// User tapped a checklist row. Switches tabs and arms the glow on the
    /// relevant element. The row itself completes when the user does the action
    /// (notification-driven).
    func tapChecklistItem(_ item: ChecklistItem, appState: AppState) {
        guard !completedItems.contains(item) else { return }
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
            checklistExpanded = false
        }
        if let tab = item.targetTab {
            withAnimation(Design.Animation.standard) {
                appState.selectedTab = tab
            }
        }
        if item == .readToday {
            // Completes on the .articleOpened event; no element-level glow.
            glowTargetItem = nil
        } else {
            triggerGlow(for: item)
        }
    }

    func triggerGlow(for item: ChecklistItem) {
        withAnimation(.easeInOut(duration: 0.25)) {
            glowTargetItem = item
        }
    }

    func dismissGlow() {
        guard glowTargetItem != nil else { return }
        withAnimation(.easeInOut(duration: 0.25)) {
            glowTargetItem = nil
        }
    }

    func complete(_ item: ChecklistItem) {
        guard !completedItems.contains(item) else { return }
        withAnimation(.spring(response: 0.5, dampingFraction: 0.75)) {
            completedItems.insert(item)
            checklistExpanded = true
            glowTargetItem = nil
        }
        UserDefaults.standard.set(true, forKey: Self.itemKey(item))

        TutorialLiveActivityController.shared.update(
            completed: completedItems,
            currentTitle: nextItem?.title ?? "All done"
        )

        if completedItems.count == ChecklistItem.allCases.count {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { [weak self] in
                withAnimation(.spring(response: 0.42, dampingFraction: 0.85)) {
                    self?.phase = .completion
                }
            }
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { [weak self] in
                guard let self, self.phase == .checklist else { return }
                withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                    self.checklistExpanded = false
                }
            }
        }
    }

    func toggleChecklistExpanded() {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
            checklistExpanded.toggle()
        }
    }

    // MARK: - Modal coordination

    func setCoveringModal(_ active: Bool) {
        guard isActive else { return }
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
            coveringModalActive = active
        }
    }

    // MARK: - Finish

    func finishCompletion(appState: AppState) {
        withAnimation(Design.Animation.standard) {
            appState.selectedTab = .today
        }
        finish()
    }

    func finish() {
        UserDefaults.standard.set(true, forKey: Self.completedKey)
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        observers = []
        TutorialLiveActivityController.shared.end()
        withAnimation(.spring(response: 0.4, dampingFraction: 0.82)) {
            phase = .dismissed
            glowTargetItem = nil
            coveringModalActive = false
        }
    }

    // MARK: - Data event observers

    private func observeDataEvents() {
        let nc = NotificationCenter.default
        observers.forEach { nc.removeObserver($0) }
        observers = [
            nc.addObserver(forName: .folderAdded, object: nil, queue: .main) { [weak self] _ in
                self?.complete(.createFolder)
            },
            nc.addObserver(forName: .feedAdded, object: nil, queue: .main) { [weak self] _ in
                self?.complete(.subscribeFirst)
            },
            nc.addObserver(forName: .articleOpened, object: nil, queue: .main) { [weak self] _ in
                self?.complete(.readToday)
            },
        ]
    }

    // MARK: - Persistence

    private func saveInterests() {
        UserDefaults.standard.set(Array(interests), forKey: Self.interestsKey)
    }

    private func loadInterests() {
        if let arr = UserDefaults.standard.stringArray(forKey: Self.interestsKey) {
            interests = Set(arr)
        }
    }

    private func loadCompletedItems() {
        var items = Set<ChecklistItem>()
        for item in ChecklistItem.allCases {
            if UserDefaults.standard.bool(forKey: Self.itemKey(item)) {
                items.insert(item)
            }
        }
        completedItems = items
    }
}

// MARK: - Glow Preference Key

/// Anchors the bounding rect of any view that should receive the tutorial's
/// attention glow when it's the active target. Rendered globally from MainTabView
/// so the glow can extend beyond clipped parent containers (e.g. toolbar buttons).
struct TutorialGlowKey: PreferenceKey {
    static var defaultValue: [TutorialManager.ChecklistItem: Anchor<CGRect>] = [:]
    static func reduce(
        value: inout [TutorialManager.ChecklistItem: Anchor<CGRect>],
        nextValue: () -> [TutorialManager.ChecklistItem: Anchor<CGRect>]
    ) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

extension View {
    /// Marks this view as the target of the tutorial's attention glow.
    func tutorialGlow(for item: TutorialManager.ChecklistItem) -> some View {
        anchorPreference(key: TutorialGlowKey.self, value: .bounds) { [item: $0] }
    }
}
