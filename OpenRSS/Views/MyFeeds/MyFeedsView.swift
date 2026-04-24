//
//  MyFeedsView.swift
//  OpenRSS
//
//  My Feeds tab — clean flat list of folder rows, liquid glass style.
//
//  Layout:
//    • Floating glass header  — title · search icon · Edit pill
//    • Search mode            — flat list of all feeds with delete buttons
//    • Normal mode            — grouped glass card with folder rows + dashed Add button
//    • Empty state            — friendly illustration + CTA button
//  Ambient glow blobs (dark mode only) reinforce the liquid glass feel.
//

import SwiftUI

struct MyFeedsView: View {

    // MARK: - State

    @State private var viewModel       = MyFeedsViewModel()
    @State private var isEditing       = false
    @State private var searchText      = ""
    @State private var isSearching     = false
    @State private var expandedFolders = Set<UUID>()

    // MARK: - Environment

    @Environment(\.colorScheme) private var colorScheme
    @Environment(AppState.self) private var appState

    // MARK: - Body

    var body: some View {
        ZStack(alignment: .top) {
            // Flat color — matches TodayView/SourcesView pattern exactly (no size inflation)
            Design.Colors.background(for: colorScheme).ignoresSafeArea()

            if !isSearching && !viewModel.hasAnyFeeds {
                // Empty state: full-height centered layout (Spacers work outside ScrollView)
                VStack {
                    Spacer()
                    emptyStateView
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .safeAreaInset(edge: .top, spacing: 0) { headerView }
                .safeAreaInset(edge: .bottom, spacing: 0) { Color.clear.frame(height: 94) }
            } else {
                ScrollView {
                    VStack(spacing: 16) {
                        if isSearching {
                            searchResultsView
                        } else {
                            feedsListView
                            addSourceButton
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 20)
                }
                .safeAreaInset(edge: .top, spacing: 0) { headerView }
                .safeAreaInset(edge: .bottom, spacing: 0) { Color.clear.frame(height: 94) }
            }
        }
        .sheet(isPresented: $viewModel.showingAddFeed) {
            AddFeedView()
        }
        .animation(Design.Animation.standard, value: isSearching)
        .animation(Design.Animation.standard, value: isEditing)
        .animation(Design.Animation.standard, value: viewModel.hasAnyFeeds)
    }

    // MARK: - Floating Glass Header

    @ViewBuilder
    private var headerView: some View {
        let totalFeeds = viewModel.folders.reduce(0) { $0 + viewModel.feeds(in: $1).count }
                       + viewModel.unfiledFeeds.count

        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("My Feeds")
                        .font(.system(size: 34, weight: .bold))
                        .foregroundStyle(Design.Colors.primaryText(for: colorScheme))

                    if viewModel.hasAnyFeeds && !isSearching {
                        Text("\(totalFeeds) feed\(totalFeeds == 1 ? "" : "s")  ·  \(viewModel.folders.count) folder\(viewModel.folders.count == 1 ? "" : "s")")
                            .font(.system(size: 13))
                            .foregroundStyle(Design.Colors.secondaryText(for: colorScheme))
                            .transition(.opacity)
                    }
                }
                .animation(Design.Animation.quick, value: isSearching)
                .animation(Design.Animation.quick, value: viewModel.hasAnyFeeds)

                Spacer()

                HStack(spacing: 10) {
                    // Search toggle
                    Button {
                        withAnimation(Design.Animation.standard) {
                            isSearching.toggle()
                            if !isSearching { searchText = "" }
                            if  isSearching { isEditing  = false }
                        }
                    } label: {
                        Image(systemName: isSearching ? "xmark.circle.fill" : "magnifyingglass")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(
                                isSearching
                                    ? Design.Colors.secondaryText(for: colorScheme)
                                    : Design.Colors.primaryText(for: colorScheme).opacity(0.85)
                            )
                            .glassButton(size: 36, colorScheme: colorScheme)
                    }
                    .buttonStyle(.plain)

                    // Edit / Done icon button
                    if viewModel.hasAnyFeeds {
                        Button {
                            withAnimation(Design.Animation.standard) {
                                isEditing.toggle()
                                if isEditing { isSearching = false; searchText = "" }
                            }
                        } label: {
                            Image(systemName: isEditing ? "checkmark" : "pencil")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(Design.Colors.primary)
                                .glassButton(size: 36, colorScheme: colorScheme)
                        }
                        .buttonStyle(.plain)
                        .transition(.scale.combined(with: .opacity))
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, isSearching ? 10 : 14)

            // Animated search bar
            if isSearching {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Design.Colors.secondaryText(for: colorScheme))

                    TextField("Search feeds…", text: $searchText)
                        .font(.system(size: 16))
                        .foregroundStyle(Design.Colors.primaryText(for: colorScheme))
                        .tint(Design.Colors.primary)
                        .autocorrectionDisabled()
                        .autocapitalization(.none)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(
                            colorScheme == .dark
                                ? Color.white.opacity(0.07)
                                : Color.black.opacity(0.05)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Design.Colors.glassBorder(for: colorScheme), lineWidth: 0.5)
                        )
                )
                .padding(.horizontal, 20)
                .padding(.bottom, 14)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .background(
            RoundedRectangle(cornerRadius: Design.Radius.glass)
                .fill(colorScheme == .dark ? .ultraThinMaterial : .regularMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: Design.Radius.glass)
                        .stroke(
                            LinearGradient(
                                colors: colorScheme == .dark
                                    ? [Color.white.opacity(0.15), Color.white.opacity(0.05)]
                                    : [Color.white.opacity(0.85), Color.black.opacity(0.05)],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 0.5
                        )
                )
                .shadow(
                    color: colorScheme == .dark ? .black.opacity(0.35) : .black.opacity(0.12),
                    radius: 20, y: 10
                )
        )
        .padding(.horizontal, 12)
        .padding(.top, 8)
    }

    // MARK: - Feeds List (one card per folder, with gaps)

    private var feedsListView: some View {
        VStack(spacing: 10) {
            ForEach(viewModel.folders) { folder in
                folderCard(folder)
            }
            if !viewModel.unfiledFeeds.isEmpty {
                unfiledCard
            }
        }
        .animation(Design.Animation.standard, value: viewModel.folders.count)
    }

    // MARK: - Folder Card (expandable)

    private func folderCard(_ folder: Category) -> some View {
        let feeds      = viewModel.feeds(in: folder)
        let unread     = viewModel.unreadCount(for: folder)
        let isExpanded = expandedFolders.contains(folder.id)

        return VStack(spacing: 0) {

            // ── Header row ──────────────────────────────────────────────
            HStack(spacing: 14) {

                // Edit-mode delete button
                if isEditing {
                    Button {
                        withAnimation(Design.Animation.standard) {
                            viewModel.deleteFolder(folder)
                        }
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.plain)
                    .transition(.scale.combined(with: .opacity))
                }

                // Icon chip
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(folder.color.opacity(isExpanded ? 0.25 : 0.15))
                        .frame(width: 46, height: 46)
                    Image(systemName: folder.icon)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(folder.color)
                }
                .shadow(color: isExpanded ? folder.color.opacity(0.35) : .clear, radius: 8)
                .animation(Design.Animation.quick, value: isExpanded)

                // Folder name + feed count
                VStack(alignment: .leading, spacing: 3) {
                    Text(folder.name)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Design.Colors.primaryText(for: colorScheme).opacity(0.92))
                    Text("\(feeds.count) feed\(feeds.count == 1 ? "" : "s")")
                        .font(.system(size: 12))
                        .foregroundStyle(Design.Colors.secondaryText(for: colorScheme))
                }

                Spacer()

                if !isEditing {
                    HStack(spacing: 10) {
                        if unread > 0 {
                            Text("\(unread) NEW")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(Design.Colors.primary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(
                                    Capsule()
                                        .fill(Design.Colors.primary.opacity(0.15))
                                        .overlay(
                                            Capsule()
                                                .stroke(Design.Colors.primary.opacity(0.3), lineWidth: 0.5)
                                        )
                                )
                                .shadow(color: Design.Colors.primary.opacity(0.25), radius: 6)
                        }

                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Design.Colors.secondaryText(for: colorScheme).opacity(0.35))
                            .rotationEffect(.degrees(isExpanded ? 90 : 0))
                            .animation(Design.Animation.quick, value: isExpanded)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 17)
            .contentShape(Rectangle())
            .onTapGesture {
                guard !isEditing else { return }
                withAnimation(Design.Animation.standard) {
                    if expandedFolders.contains(folder.id) {
                        expandedFolders.remove(folder.id)
                    } else {
                        expandedFolders.insert(folder.id)
                    }
                }
            }

            // ── Expanded feed rows ────────────────────────────────────
            if isExpanded && !feeds.isEmpty {
                etchedSeparator

                ForEach(Array(feeds.enumerated()), id: \.element.id) { idx, feed in
                    feedSubRow(feed)
                    if idx < feeds.count - 1 {
                        etchedSeparator
                            .padding(.leading, 60)
                    }
                }
                .padding(.bottom, 6)
            }
        }
        .background(glassCard)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .animation(Design.Animation.standard, value: isExpanded)
        .animation(Design.Animation.standard, value: isEditing)
    }

    // MARK: - Feed Sub-Row

    private func feedSubRow(_ feed: Source) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 7)
                    .fill(feed.iconColor.opacity(0.15))
                    .frame(width: 32, height: 32)
                Image(systemName: feed.icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(feed.iconColor)
            }
            .padding(.leading, 8)

            VStack(alignment: .leading, spacing: 1) {
                Text(feed.name)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Design.Colors.primaryText(for: colorScheme))
                    .lineLimit(1)
                Text(feed.websiteURL)
                    .font(.system(size: 11))
                    .foregroundStyle(Design.Colors.secondaryText(for: colorScheme))
                    .lineLimit(1)
            }

            Spacer()

            // Lock indicator when feed is manually marked as paywalled
            if feed.isPaywalled && !isEditing {
                Image(systemName: "lock.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(Design.Colors.secondaryText(for: colorScheme).opacity(0.6))
            }

            if isEditing {
                Button {
                    withAnimation(Design.Animation.standard) {
                        viewModel.deleteFeed(feed)
                    }
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(.red.opacity(0.9))
                }
                .buttonStyle(.plain)
                .padding(.trailing, 4)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .contextMenu {
            Button {
                viewModel.togglePaywalled(feed)
            } label: {
                Label(
                    feed.isPaywalled ? "Remove Paywall Flag" : "Mark as Paywalled",
                    systemImage: feed.isPaywalled ? "lock.slash" : "lock.fill"
                )
            }
            Button(role: .destructive) {
                withAnimation(Design.Animation.standard) {
                    viewModel.deleteFeed(feed)
                }
            } label: {
                Label("Delete Feed", systemImage: "trash")
            }
        }
    }

    // MARK: - Unfiled Card

    private var unfiledCard: some View {
        let feeds      = viewModel.unfiledFeeds
        let isExpanded = expandedFolders.contains(SwiftDataService.unfiledFolderID)

        return VStack(spacing: 0) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.gray.opacity(0.15))
                        .frame(width: 46, height: 46)
                    Image(systemName: "tray")
                        .font(.system(size: 19, weight: .medium))
                        .foregroundStyle(Color.gray)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text("Unfiled")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Design.Colors.primaryText(for: colorScheme).opacity(0.92))
                    Text("\(feeds.count) feed\(feeds.count == 1 ? "" : "s")")
                        .font(.system(size: 12))
                        .foregroundStyle(Design.Colors.secondaryText(for: colorScheme))
                }

                Spacer()

                if !isEditing {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Design.Colors.secondaryText(for: colorScheme).opacity(0.35))
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .animation(Design.Animation.quick, value: isExpanded)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 17)
            .contentShape(Rectangle())
            .onTapGesture {
                guard !isEditing else { return }
                withAnimation(Design.Animation.standard) {
                    if expandedFolders.contains(SwiftDataService.unfiledFolderID) {
                        expandedFolders.remove(SwiftDataService.unfiledFolderID)
                    } else {
                        expandedFolders.insert(SwiftDataService.unfiledFolderID)
                    }
                }
            }

            if isExpanded && !feeds.isEmpty {
                etchedSeparator
                ForEach(Array(feeds.enumerated()), id: \.element.id) { idx, feed in
                    feedSubRow(feed)
                    if idx < feeds.count - 1 {
                        etchedSeparator.padding(.leading, 60)
                    }
                }
                .padding(.bottom, 6)
            }
        }
        .background(glassCard)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .animation(Design.Animation.standard, value: isExpanded)
    }

    // MARK: - Search Results

    @ViewBuilder
    private var searchResultsView: some View {
        let results = viewModel.filteredAllFeeds(matching: searchText)

        if results.isEmpty {
            VStack(spacing: 14) {
                Image(systemName: searchText.isEmpty ? "list.bullet" : "magnifyingglass")
                    .font(.system(size: 32, weight: .ultraLight))
                    .foregroundStyle(Design.Colors.secondaryText(for: colorScheme).opacity(0.4))

                Text(
                    searchText.isEmpty
                        ? "No feeds subscribed yet"
                        : "No feeds matching \"\(searchText)\""
                )
                .font(.system(size: 15))
                .foregroundStyle(Design.Colors.secondaryText(for: colorScheme))
                .multilineTextAlignment(.center)
            }
            .padding(.top, 50)
            .frame(maxWidth: .infinity)
        } else {
            VStack(spacing: 0) {
                ForEach(Array(results.enumerated()), id: \.element.id) { index, feed in
                    searchFeedRow(feed)
                    if index < results.count - 1 {
                        etchedSeparator
                    }
                }
            }
            .background(glassCard)
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
    }

    private func searchFeedRow(_ feed: Source) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(feed.iconColor.opacity(0.15))
                    .frame(width: 36, height: 36)
                Image(systemName: feed.icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(feed.iconColor)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(feed.name)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Design.Colors.primaryText(for: colorScheme).opacity(0.92))
                    .lineLimit(1)
                Text(viewModel.folderName(for: feed))
                    .font(.system(size: 11))
                    .foregroundStyle(Design.Colors.secondaryText(for: colorScheme).opacity(0.7))
            }

            Spacer()

            // Lock indicator when feed is manually marked as paywalled
            if feed.isPaywalled {
                Image(systemName: "lock.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(Design.Colors.secondaryText(for: colorScheme).opacity(0.6))
            }

            Button {
                withAnimation(Design.Animation.standard) {
                    viewModel.deleteFeed(feed)
                }
            } label: {
                Image(systemName: "minus.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(.red.opacity(0.9))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .contentShape(Rectangle())
        .contextMenu {
            Button {
                viewModel.togglePaywalled(feed)
            } label: {
                Label(
                    feed.isPaywalled ? "Remove Paywall Flag" : "Mark as Paywalled",
                    systemImage: feed.isPaywalled ? "lock.slash" : "lock.fill"
                )
            }
            Button(role: .destructive) {
                withAnimation(Design.Animation.standard) {
                    viewModel.deleteFeed(feed)
                }
            } label: {
                Label("Delete Feed", systemImage: "trash")
            }
        }
    }

    // MARK: - Add Source Button

    private var addSourceButton: some View {
        Button {
            viewModel.showingAddFeed = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "plus.circle")
                    .font(.system(size: 18))
                Text("Add New Source")
                    .font(.system(size: 15, weight: .medium))
            }
            .foregroundStyle(Design.Colors.secondaryText(for: colorScheme))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(
                        colorScheme == .dark
                            ? Color.white.opacity(0.02)
                            : Color.black.opacity(0.02)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(
                                colorScheme == .dark
                                    ? Color.white.opacity(0.14)
                                    : Color.black.opacity(0.14),
                                style: StrokeStyle(lineWidth: 1, dash: [6, 4])
                            )
                    )
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 28) {
            // Icon
            ZStack {
                RoundedRectangle(cornerRadius: 28)
                    .fill(Design.Colors.primary.opacity(0.10))
                    .frame(width: 88, height: 88)
                    .overlay(
                        RoundedRectangle(cornerRadius: 28)
                            .stroke(Design.Colors.primary.opacity(0.2), lineWidth: 1)
                    )
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.system(size: 36, weight: .light))
                    .foregroundStyle(Design.Colors.primary)
            }

            // Text
            VStack(spacing: 8) {
                Text("No Feeds Yet")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(Design.Colors.primaryText(for: colorScheme))

                Text("Subscribe to RSS feeds from your favorite\nblogs, news sites, and podcasts.")
                    .font(.system(size: 15))
                    .foregroundStyle(Design.Colors.secondaryText(for: colorScheme))
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
            }

            // Actions
            VStack(spacing: 14) {
                Button {
                    viewModel.showingAddFeed = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "plus")
                            .font(.system(size: 14, weight: .semibold))
                        Text("Add Your First Feed")
                            .font(.system(size: 16, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 28)
                    .padding(.vertical, 14)
                    .background(
                        Capsule()
                            .fill(Design.Colors.primary)
                            .shadow(color: Design.Colors.primary.opacity(0.4), radius: 12, y: 4)
                    )
                }
                .buttonStyle(.plain)

                Button {
                    withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
                        appState.selectedTab = .discover
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "safari")
                            .font(.system(size: 13))
                        Text("Browse Discover")
                            .font(.system(size: 14))
                    }
                    .foregroundStyle(Design.Colors.primary.opacity(0.8))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 40)
    }

    // MARK: - Private Helpers

    private var etchedSeparator: some View {
        LinearGradient(
            colors: [
                .clear,
                colorScheme == .dark ? .white.opacity(0.10) : .black.opacity(0.07),
                .clear
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
        .frame(height: 0.5)
        .padding(.horizontal, 16)
    }

    private var glassCard: some View {
        RoundedRectangle(cornerRadius: 16)
            .fill(colorScheme == .dark ? .ultraThinMaterial : .regularMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(
                        LinearGradient(
                            colors: colorScheme == .dark
                                ? [Color.white.opacity(0.15), Color.white.opacity(0.05)]
                                : [Color.white.opacity(0.95), Color.black.opacity(0.06)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.5
                    )
            )
    }
}

// MARK: - Preview

#Preview {
    MyFeedsView()
}
