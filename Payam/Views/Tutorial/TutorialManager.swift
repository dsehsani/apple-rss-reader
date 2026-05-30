//
//  TutorialManager.swift
//  Payam
//
//  @Observable singleton driving the optional first-run interactive tutorial.
//  MainTabView observes `isActive` / `currentStep` and renders the overlay.
//

import SwiftUI

// MARK: - TutorialStep

enum TutorialStep: Int, CaseIterable, Equatable {
    case whatIsRSS       = 0  // full-screen intro
    case todayFeed       = 1  // spotlight
    case sources         = 2  // spotlight
    case createFolder    = 3  // interactive — auto-advances when folder is created
    case addFromDiscover = 4  // interactive — auto-advances when source is added
    case deleteFolder    = 5  // interactive — auto-advances when folder is deleted
    case done            = 6  // full-screen completion

    // MARK: Properties

    /// Which tab to switch to when this step becomes active. nil = stay.
    var targetTab: AppTab? {
        switch self {
        case .todayFeed:                        return .today
        case .sources, .createFolder,
             .deleteFolder:                     return .saved
        case .addFromDiscover:                  return .discover
        default:                                return nil
        }
    }

    /// Full-screen modal card with no spotlight or card.
    var isFullScreen: Bool { self == .whatIsRSS || self == .done }

    /// Show a spotlight cutout (only informational non-full-screen steps).
    var hasSpotlight: Bool {
        self == .todayFeed || self == .sources
    }

    /// App is fully interactive — no blocking scrim, just a floating card.
    var isInteractive: Bool {
        switch self {
        case .createFolder, .addFromDiscover, .deleteFolder: return true
        default: return false
        }
    }

    // MARK: Content

    var title: String {
        switch self {
        case .whatIsRSS:       return "What is RSS?"
        case .todayFeed:       return "Your Feed"
        case .sources:         return "Your Sources"
        case .createFolder:    return "Create a Folder"
        case .addFromDiscover: return "Add a Feed"
        case .deleteFolder:    return "Clean Up (Optional)"
        case .done:            return "You're all set!"
        }
    }

    var body: String {
        switch self {
        case .whatIsRSS:
            return "RSS is how websites publish updates. When a blog posts an article or a YouTube channel uploads a video, it appears in an RSS feed — like a live inbox for content.\n\nInstead of checking every site manually or relying on an algorithm, Payam pulls all your subscriptions into one clean, ranked river. You choose what you follow. No ads, no tracking."

        case .todayFeed:
            return "This is your river — every new article from the feeds you follow, ranked by freshness. Pull down to refresh, or use the folder tabs at the top to filter by topic."

        case .sources:
            return "This is where all your subscriptions live, organized into folder tiles. Tap any folder to see the feeds inside it. Now let's actually build one together."

        case .createFolder:
            return "Tap the + button in the top right corner.\n\nIn the menu that appears, tap New Folder. Give it a name, pick a color, and choose an icon — then tap Create.\n\nThe tour moves forward automatically once your folder is created."

        case .addFromDiscover:
            return "You're now in Discover. Browse by category or scroll the featured feeds.\n\nWhen you find one you like, tap its + button. A folder picker will slide up — select the folder you just created.\n\nThe tour moves forward automatically once you subscribe to a feed."

        case .deleteFolder:
            return "The folder you created is yours to keep. If you made it just for practice, you can remove it now.\n\nTo delete: tap the folder tile, then tap Edit Folder → Delete Folder.\n\nOtherwise, tap Finish Tour below."

        case .done:
            return "Your first folder and feed are set up. Explore Discover to find more, or add any RSS URL manually from Sources. You can replay this tour anytime from Settings → Tour."
        }
    }

    var icon: String {
        switch self {
        case .whatIsRSS:       return "dot.radiowaves.left.and.right"
        case .todayFeed:       return "newspaper.fill"
        case .sources:         return "antenna.radiowaves.left.and.right"
        case .createFolder:    return "folder.badge.plus"
        case .addFromDiscover: return "plus.square.fill"
        case .deleteFolder:    return "trash"
        case .done:            return "checkmark.circle.fill"
        }
    }

    // 1-based position among all non-full-screen steps for the "X of Y" counter.
    var stepIndex: Int {
        let steps = TutorialStep.allCases.filter { !$0.isFullScreen }
        return (steps.firstIndex(of: self) ?? 0) + 1
    }

    static var stepCount: Int {
        TutorialStep.allCases.filter { !$0.isFullScreen }.count
    }
}

// MARK: - TutorialManager

@Observable
final class TutorialManager {

    static let shared = TutorialManager()
    private static let completedKey = "payam.tutorial.completed"

    var isActive: Bool = false
    var currentStep: TutorialStep = .whatIsRSS

    private var observers: [NSObjectProtocol] = []

    private init() {}

    func startIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: Self.completedKey) else { return }
        start()
    }

    func start() {
        currentStep = .whatIsRSS
        withAnimation(.spring(response: 0.4, dampingFraction: 0.82)) {
            isActive = true
        }
        observeDataEvents()
    }

    private func observeDataEvents() {
        let nc = NotificationCenter.default
        observers.forEach { nc.removeObserver($0) }
        observers = [
            nc.addObserver(forName: .folderAdded, object: nil, queue: .main) { [weak self] _ in
                guard let self, self.currentStep == .createFolder else { return }
                self.advance()
            },
            nc.addObserver(forName: .feedAdded, object: nil, queue: .main) { [weak self] _ in
                guard let self, self.currentStep == .addFromDiscover else { return }
                self.advance()
            },
            nc.addObserver(forName: .folderDeleted, object: nil, queue: .main) { [weak self] _ in
                guard let self, self.currentStep == .deleteFolder else { return }
                self.advance()
            },
        ]
    }

    func advance() {
        let all = TutorialStep.allCases
        guard let idx = all.firstIndex(of: currentStep) else { return }
        if idx + 1 < all.count {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                currentStep = all[idx + 1]
            }
        } else {
            finish()
        }
    }

    func finish() {
        UserDefaults.standard.set(true, forKey: Self.completedKey)
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        observers = []
        withAnimation(.spring(response: 0.4, dampingFraction: 0.82)) {
            isActive = false
        }
    }
}

// MARK: - Spotlight Anchor Preference Key

struct TutorialSpotlightKey: PreferenceKey {
    static var defaultValue: [TutorialStep: Anchor<CGRect>] = [:]
    static func reduce(
        value: inout [TutorialStep: Anchor<CGRect>],
        nextValue: () -> [TutorialStep: Anchor<CGRect>]
    ) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

// MARK: - View Modifier Helper

extension View {
    func tutorialSpotlight(for step: TutorialStep) -> some View {
        anchorPreference(key: TutorialSpotlightKey.self, value: .bounds) { anchor in
            [step: anchor]
        }
    }

    /// Draws a pulsing attention ring on any view when the tutorial is on the given step.
    func tutorialPulse(for step: TutorialStep) -> some View {
        modifier(TutorialPulseModifier(step: step))
    }
}

// MARK: - Pulsing Attention Ring

private struct TutorialPulseModifier: ViewModifier {
    let step: TutorialStep
    @State private var phase: Bool = false

    func body(content: Content) -> some View {
        let isOn = TutorialManager.shared.isActive && TutorialManager.shared.currentStep == step
        content
            .overlay(
                Circle()
                    .stroke(Design.Colors.primary, lineWidth: 2.5)
                    .scaleEffect(phase ? 2.0 : 1.0)
                    .opacity(phase ? 0 : 0.85)
                    .allowsHitTesting(false)
                    .opacity(isOn ? 1 : 0)
                    .animation(.easeOut(duration: 1.1).repeatForever(autoreverses: false), value: phase)
            )
            .onAppear { if isOn { phase = false; phase = true } }
            .onChange(of: isOn) { _, on in
                phase = false
                if on { phase = true }
            }
    }
}
