//
//  TodayView.swift
//  OpenRSS
//
//  Created by Darius Ehsani on 2/3/26.
//

import SwiftUI

/// Main Today feed view with articles and category filtering
struct TodayView: View {

    // MARK: - ViewModel

    @State private var viewModel = TodayViewModel()

    // MARK: - State

    @State private var showingSearch = false
    @State private var showingFilter = false
    @State private var showingArchive = false
    @State private var selectedArticle: Article? = nil

    // MARK: - Environment (Light/Dark Mode)

    @Environment(\.colorScheme) private var colorScheme

    // MARK: - Body

    var body: some View {
        NavigationStack {
        ZStack(alignment: .top) {
            // Background - adaptive for light/dark mode
            Design.Colors.background(for: colorScheme).ignoresSafeArea()

            // Main content — safeAreaInset automatically adapts header/footer to any device
            ScrollView {
                LazyVStack(spacing: Design.Spacing.cardGap) {
                    // Empty states
                    if viewModel.filteredArticles.isEmpty {
                        if !viewModel.hasSources {
                            noFeedsPrompt
                        } else {
                            noResultsPrompt
                        }
                    } else {
                        // Articles
                        ForEach(viewModel.filteredArticles) { article in
                            ArticleCardView(
                                article: article,
                                source: viewModel.source(for: article),
                                decayScore: viewModel.isSearchActive ? 1.0 : viewModel.decayScore(for: article),
                                clusterBadge: viewModel.clusterBadge(for: article).map { badge in
                                    var b = badge
                                    b.onSiblingTap = { sibling in
                                        viewModel.markAsRead(sibling)
                                        selectedArticle = sibling
                                    }
                                    return b
                                },
                                onBookmarkTap: {
                                    viewModel.toggleBookmark(for: article)
                                },
                                onReadMoreTap: {
                                    viewModel.markAsRead(article)
                                    selectedArticle = article
                                },
                                onSplitCluster: {
                                    viewModel.splitCluster(for: article)
                                }
                            )
                            .padding(.horizontal, Design.Spacing.edge)
                        }

                        // Task 2: Sparse results indicator
                        if viewModel.isSearchActive {
                            let count = viewModel.filteredArticles.count
                            if count > 0 && count < 5 {
                                VStack(spacing: 4) {
                                    Text("Only \(count) result\(count == 1 ? "" : "s") found")
                                        .font(.system(size: 13))
                                        .foregroundStyle(Design.Colors.secondaryText(for: colorScheme))
                                    Text("across 30 days of cached articles")
                                        .font(.system(size: 13))
                                        .foregroundStyle(Design.Colors.secondaryText(for: colorScheme))
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                            }
                        }
                    }
                }
            }
            .refreshable {
                await viewModel.refresh()
            }
            // Floating glass header — insets scroll content by the header's actual height
            .safeAreaInset(edge: .top, spacing: 0) {
                floatingGlassHeader
            }
            // Tab bar clearance — 70pt bar + 24pt bottom padding = 94pt above safe area
            .safeAreaInset(edge: .bottom, spacing: 0) {
                Color.clear.frame(height: 94)
            }
        }
        .sheet(isPresented: $showingFilter) {
            LiquidGlassFilterSheet(activeFilters: $viewModel.activeFilters)
        }
        .navigationDestination(item: $selectedArticle) { article in
            ArticleReaderHostView(
                article: article,
                feedName: viewModel.source(for: article)?.name ?? "Article"
            )
        }
        .navigationDestination(isPresented: $showingArchive) {
            ArchiveView()
        }
        // Auto-refresh on first appearance; skips if a refresh ran < 30 min ago.
        .task {
            await viewModel.autoRefreshIfNeeded()
        }
        } // NavigationStack
    }

    // MARK: - Floating Glass Header
    // Rendered via .safeAreaInset — no outer Spacer needed; height is self-sizing.

    private var floatingGlassHeader: some View {
        VStack(spacing: 12) {

            // Top row — switches between title+controls and the search bar
            ZStack {
                // Title row — visible when search is inactive
                if !showingSearch {
                    titleRow
                        .transition(
                            .asymmetric(
                                insertion: .scale(scale: 0.95, anchor: .leading).combined(with: .opacity),
                                removal:   .scale(scale: 0.95, anchor: .leading).combined(with: .opacity)
                            )
                        )
                }

                // Search bar — slides in from the trailing edge when active
                if showingSearch {
                    LiquidGlassSearchBar(
                        text:     $viewModel.searchViewModel.searchText,
                        isActive: $showingSearch
                    )
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                }
            }
            .animation(Design.Animation.standard, value: showingSearch)

            // Category chips — always visible
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(viewModel.allCategories) { category in
                        CategoryChipView(
                            category: category,
                            isSelected: viewModel.selectedCategory?.id == category.id,
                            unreadCount: viewModel.unreadCount(for: category)
                        ) {
                            viewModel.selectCategory(category)
                        }
                    }
                }
                .padding(.horizontal, 20)
            }
            .padding(.bottom, 16)
        }
        .background(
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
                .shadow(color: colorScheme == .dark ? .black.opacity(0.3) : .black.opacity(0.15), radius: 20, y: 10)
        )
        .padding(.horizontal, 12)
        .padding(.top, 8)
    }

    // MARK: - Title Row (search inactive state)

    private var titleRow: some View {
        HStack(alignment: .center) {
            // Title on left
            Text("Today")
                .font(Design.Typography.largeTitle)
                .foregroundStyle(Design.Colors.primaryText(for: colorScheme))

            Spacer()

            // Controls: Archive + Filter + Search
            HStack(spacing: 12) {
                // Archive button
                Button {
                    showingArchive = true
                } label: {
                    Image(systemName: "archivebox")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(Design.Colors.primaryText(for: colorScheme).opacity(0.9))
                        .glassButton(size: 38, colorScheme: colorScheme)
                }
                .buttonStyle(.plain)

                // Filter button — blue badge dot appears when any filter is active
                Button {
                    showingFilter = true
                } label: {
                    Image(systemName: Design.Icons.filter)
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(
                            viewModel.hasActiveFilters
                                ? Design.Colors.primary
                                : Design.Colors.primaryText(for: colorScheme).opacity(0.9)
                        )
                        .glassButton(size: 38, colorScheme: colorScheme)
                        .overlay(alignment: .topTrailing) {
                            if viewModel.hasActiveFilters {
                                Circle()
                                    .fill(Design.Colors.primary)
                                    .frame(width: 9, height: 9)
                                    .overlay(Circle().stroke(Design.Colors.background(for: colorScheme), lineWidth: 1.5))
                                    .offset(x: 2, y: -2)
                                    .transition(.scale(scale: 0.3).combined(with: .opacity))
                            }
                        }
                        .animation(Design.Animation.quick, value: viewModel.hasActiveFilters)
                }
                .buttonStyle(.plain)

                // Search button — activates the LiquidGlassSearchBar with animation
                Button {
                    withAnimation(Design.Animation.standard) {
                        showingSearch = true
                    }
                } label: {
                    Image(systemName: Design.Icons.search)
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(Design.Colors.primaryText(for: colorScheme).opacity(0.9))
                        .glassButton(size: 38, colorScheme: colorScheme)
                }
                .buttonStyle(.plain)
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

// MARK: - Preview

#Preview {
    TodayView()
}
