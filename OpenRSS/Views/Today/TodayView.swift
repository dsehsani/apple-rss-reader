//
//  TodayView.swift
//  OpenRSS
//
//  Created by Darius Ehsani on 2/3/26.
//
//  Phase 2a — Now driven by RiverViewModel with decay-based opacity.
//

import SwiftUI

/// Main Today feed view with articles and category filtering
struct TodayView: View {

    // MARK: - ViewModel (Phase 2a: switched from TodayViewModel to RiverViewModel)

    @State private var viewModel = RiverViewModel()

    // MARK: - State

    @State private var selectedArticle: Article? = nil

    // MARK: - Environment

    @Environment(\.colorScheme) private var colorScheme
    @Environment(AppState.self)  private var appState

    // MARK: - Body

    var body: some View {
        NavigationStack {
        ZStack(alignment: .top) {
            // Background - adaptive for light/dark mode
            Design.Colors.background(for: colorScheme).ignoresSafeArea()

            // Main content — header scrolls with content, not sticky
            ScrollView {
                VStack(spacing: 0) {
                    headerView
                    LazyVStack(spacing: Design.Spacing.cardGap) {
                    // Empty states
                    if viewModel.filteredRiverItems.isEmpty {
                        if !viewModel.hasSources {
                            noFeedsPrompt
                        } else {
                            noResultsPrompt
                        }
                    } else {
                        // River items: articles, clusters, nudges
                        ForEach(viewModel.filteredRiverItems) { riverItem in
                            let relevance = riverItem.relevanceScore
                            let decayOpacity = DecayScoringService.opacity(for: relevance)
                            let fontScale = DecayScoringService.fontScale(for: relevance)

                            Group {
                                switch riverItem {
                                case .article(let feedItem):
                                    if let source = viewModel.source(for: feedItem) {
                                        let article = feedItem.toArticle(categoryID: source.categoryID)
                                        ArticleCardView(
                                            article: article,
                                            source: source,
                                            onBookmarkTap: {
                                                viewModel.toggleBookmark(for: article)
                                                // Phase 2d — track share/bookmark as articleShare
                                                AffinityTracker.shared.record(
                                                    .articleShare,
                                                    sourceID: article.sourceID,
                                                    itemID: article.id
                                                )
                                            },
                                            onReadMoreTap: {
                                                viewModel.markAsRead(article)
                                                selectedArticle = article
                                                // Phase 2d — track article open
                                                AffinityTracker.shared.record(
                                                    .articleOpen,
                                                    sourceID: article.sourceID,
                                                    itemID: article.id
                                                )
                                            }
                                        )
                                    }

                                case .cluster(let card):
                                    ClusterCardView(
                                        cluster: card,
                                        source: viewModel.source(for: card.canonicalItem),
                                        onArticleTap: { feedItem in
                                            if let source = viewModel.source(for: feedItem) {
                                                let article = feedItem.toArticle(categoryID: source.categoryID)
                                                viewModel.markAsRead(article)
                                                selectedArticle = article
                                            }
                                        },
                                        sourceForItem: { feedItem in
                                            viewModel.source(for: feedItem)
                                        }
                                    )

                                case .digest(let digestCard):
                                    DigestCardView(
                                        digest: digestCard,
                                        source: viewModel.source(forSourceID: digestCard.sourceID)
                                    )

                                case .nudge(let nudgeCard):
                                    NudgeCardView(
                                        nudge: nudgeCard,
                                        source: viewModel.source(forSourceID: nudgeCard.sourceID)
                                    )
                                }
                            }
                            .opacity(decayOpacity)
                            .scaleEffect(x: 1, y: fontScale, anchor: .top)
                            .padding(.horizontal, Design.Spacing.edge)
                            // Phase 2d — scroll velocity tracking
                            .modifier(ScrollDwellModifier(riverItem: riverItem))
                            // Phase 2d — explicit dismiss via context menu
                            .contextMenu {
                                if case .article(let feedItem) = riverItem {
                                    Button(role: .destructive) {
                                        AffinityTracker.shared.record(
                                            .explicitDismiss,
                                            sourceID: feedItem.sourceID,
                                            itemID: feedItem.id
                                        )
                                    } label: {
                                        Label("Not interested", systemImage: "hand.thumbsdown")
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(.top, Design.Spacing.cardGap)
                } // close VStack
            }
            .refreshable {
                await viewModel.refresh()
            }
            // Tab bar clearance — 70pt bar + 24pt bottom padding = 94pt above safe area
            .safeAreaInset(edge: .bottom, spacing: 0) {
                Color.clear.frame(height: 94)
            }
        }
        .navigationDestination(item: $selectedArticle) { article in
            ArticleReaderHostView(
                article: article,
                feedName: viewModel.source(for: article)?.name ?? "Article"
            )
        }
        // Auto-refresh on first appearance; skips if a refresh ran < 30 min ago.
        .task {
            await viewModel.autoRefreshIfNeeded()
        }
        } // NavigationStack
    }

    // MARK: - Header (scrolls with content)

    private var headerView: some View {
        VStack(spacing: 0) {
            titleRow

            // Category chips
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(viewModel.allCategories) { category in
                        categoryButton(category)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 10)
                .padding(.bottom, 14)
            }
        }
        .background {
            if #available(iOS 26.0, *) {
                Color.clear
                    .glassEffect(in: RoundedRectangle(cornerRadius: Design.Radius.glass))
            } else {
                RoundedRectangle(cornerRadius: Design.Radius.glass)
                    .fill(colorScheme == .dark ? .ultraThinMaterial : .regularMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: Design.Radius.glass)
                            .stroke(
                                LinearGradient(
                                    colors: colorScheme == .dark
                                        ? [Color.white.opacity(0.25), Color.white.opacity(0.1), Color.white.opacity(0.05)]
                                        : [Color.white.opacity(0.8), Color.white.opacity(0.4), Color.black.opacity(0.05)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                ),
                                lineWidth: 0.5
                            )
                    )
                    .shadow(color: colorScheme == .dark ? .black.opacity(0.3) : .black.opacity(0.08), radius: 16, y: 6)
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
    }

    // MARK: - Category Button

    private func categoryButton(_ category: Category) -> some View {
        let isSelected = viewModel.selectedCategory?.id == category.id
        let unread = viewModel.unreadCount(for: category)

        return Button {
            viewModel.selectCategory(category)
            // Sync the active folder to AppState so SearchView can auto-scope
            // when the user switches to the Search tab.
            appState.activeFolderCategoryID = category.id == Category.allUpdates.id
                ? nil
                : category.id
        } label: {
            HStack(spacing: 6) {
                Image(systemName: category.icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(isSelected ? .white : category.color)

                Text(category.name)
                    .font(.system(size: 14, weight: isSelected ? .semibold : .medium))
                    .foregroundStyle(
                        isSelected
                            ? .white
                            : Design.Colors.primaryText(for: colorScheme)
                    )

                if unread > 0 && !isSelected {
                    Text("\(unread)")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(category.color.opacity(0.75))
                        .clipShape(Capsule())
                }
            }
            .padding(.horizontal, 14)
            .frame(height: 36)
            .background {
                if isSelected {
                    Capsule()
                        .fill(category.color)
                        .overlay(
                            Capsule()
                                .stroke(
                                    LinearGradient(
                                        colors: [Color.white.opacity(0.45), Color.white.opacity(0.1)],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    ),
                                    lineWidth: 0.5
                                )
                        )
                        .shadow(color: category.color.opacity(0.4), radius: 8, y: 3)
                } else {
                    if #available(iOS 26.0, *) {
                        Color.clear
                            .glassEffect(in: Capsule())
                    } else {
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
                                color: colorScheme == .dark ? .black.opacity(0.4) : .black.opacity(0.07),
                                radius: colorScheme == .dark ? 8 : 4,
                                y: colorScheme == .dark ? 3 : 2
                            )
                    }
                }
            }
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .animation(Design.Animation.quick, value: isSelected)
    }

    // MARK: - Title Row

    private var titleRow: some View {
        HStack(alignment: .top) {
            HelloDrawView(height: 36)

            Spacer()

            // Native pop-up filter menu
            Menu {
                ForEach(FilterOption.allCases) { option in
                    let isActive = viewModel.activeFilters.contains(option)
                    Button {
                        withAnimation(Design.Animation.standard) {
                            if isActive {
                                viewModel.activeFilters.remove(option)
                            } else {
                                viewModel.activeFilters.insert(option)
                            }
                        }
                    } label: {
                        Label(
                            option.rawValue,
                            systemImage: isActive ? "checkmark" : option.icon
                        )
                    }
                    .tint(isActive ? Design.Colors.primary : .primary)
                }

                if !viewModel.activeFilters.isEmpty {
                    Divider()
                    Button(role: .destructive) {
                        withAnimation(Design.Animation.standard) {
                            viewModel.activeFilters.removeAll()
                        }
                    } label: {
                        Label("Clear All", systemImage: "xmark.circle")
                    }
                }
            } label: {
                Image(systemName: Design.Icons.filter)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(
                        viewModel.hasActiveFilters
                            ? Design.Colors.primary
                            : Design.Colors.primaryText(for: colorScheme).opacity(0.85)
                    )
                    .glassButton(size: 36, colorScheme: colorScheme)
                    .overlay(alignment: .topTrailing) {
                        if viewModel.hasActiveFilters {
                            Circle()
                                .fill(Design.Colors.primary)
                                .frame(width: 8, height: 8)
                                .overlay(Circle().stroke(Design.Colors.background(for: colorScheme), lineWidth: 1.5))
                                .offset(x: 2, y: -2)
                                .transition(.scale(scale: 0.3).combined(with: .opacity))
                        }
                    }
                    .animation(Design.Animation.quick, value: viewModel.hasActiveFilters)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
    }

    // MARK: - Empty States

    /// Shown when the user hasn't subscribed to any feeds yet.
    private var noFeedsPrompt: some View {
        VStack(spacing: Design.Spacing.section) {
            Image(systemName: "dot.radiowaves.left.and.right")
                .font(.system(size: 52, weight: .ultraLight))
                .foregroundStyle(Design.Colors.primary.opacity(0.45))

            VStack(spacing: Design.Spacing.small) {
                Text("No Feeds Yet")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Design.Colors.primaryText(for: colorScheme))

                Text("Head to My Feeds to subscribe\nto your first RSS feed.")
                    .font(.system(size: 15))
                    .foregroundStyle(Design.Colors.secondaryText(for: colorScheme))
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.top, 60)
        .padding(.horizontal, Design.Spacing.section)
        .frame(maxWidth: .infinity)
    }

    /// Shown when feeds exist but search/filter returned no results.
    private var noResultsPrompt: some View {
        VStack(spacing: Design.Spacing.small) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 36, weight: .ultraLight))
                .foregroundStyle(Design.Colors.secondaryText(for: colorScheme).opacity(0.6))

            Text("No Results")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Design.Colors.primaryText(for: colorScheme))

            Text("Try a different search or filter.")
                .font(.system(size: 14))
                .foregroundStyle(Design.Colors.secondaryText(for: colorScheme))
        }
        .padding(.top, 60)
        .frame(maxWidth: .infinity)
    }

}

// MARK: - Scroll Dwell Tracking (Phase 2d)

/// Measures how long a river item card stays on screen during scrolling.
/// - Visible < 1s → scrollFastPast (user zipped past)
/// - Visible 2–8s → scrollSlow (user paused / read headline)
/// Items opened via tap are excluded (handled by articleOpen / dwell events).
private struct ScrollDwellModifier: ViewModifier {
    let riverItem: RiverItem

    @State private var appearedAt: Date?

    func body(content: Content) -> some View {
        content
            .onAppear { appearedAt = Date() }
            .onDisappear {
                guard let appeared = appearedAt else { return }
                let visibleSeconds = Date().timeIntervalSince(appeared)

                // Only track for article items (clusters/digests have their own events)
                guard case .article(let feedItem) = riverItem else { return }

                if visibleSeconds < 1.0 {
                    AffinityTracker.shared.record(
                        .scrollFastPast,
                        sourceID: feedItem.sourceID,
                        itemID: feedItem.id
                    )
                } else if visibleSeconds >= 2.0 && visibleSeconds <= 8.0 {
                    AffinityTracker.shared.record(
                        .scrollSlow,
                        sourceID: feedItem.sourceID,
                        itemID: feedItem.id
                    )
                }
                // 1-2s is ambiguous (normal scroll speed) — no event fired.
                // >8s likely means the card stayed on screen while idle — no event.
            }
    }
}

// MARK: - Preview

#Preview {
    TodayView()
}
