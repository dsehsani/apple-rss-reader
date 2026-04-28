//
//  MyFeedsView.swift
//  OpenRSS
//
//  Feeds tab — square folder widgets, Discover-style header, search + add button.
//

import SwiftUI

// MARK: - Shared folder appearance options

let folderColorHexOptions: [String] = [
    "007AFF", "FF9500", "34C759", "AF52DE", "FF2D55",
    "5AC8FA", "FF3B30", "5856D0", "FFCC00", "00C7BE"
]

let folderIconOptions: [String] = [
    "folder.fill",        "star.fill",      "heart.fill",    "bookmark.fill",
    "newspaper.fill",     "laptopcomputer", "gamecontroller.fill", "music.note",
    "camera.fill",        "cart.fill",      "globe",         "leaf.fill",
    "flame.fill",         "bolt.fill",      "person.fill",   "airplane"
]

// MARK: - Wrapper to make Category identifiable for sheet(item:)

private struct EditableFolderWrapper: Identifiable {
    let id: UUID
    let folder: Category
    init(_ folder: Category) { self.id = folder.id; self.folder = folder }
}

struct MyFeedsView: View {

    // MARK: - State

    @State private var viewModel          = MyFeedsViewModel()
    @State private var searchText         = ""
    @State private var isSearching        = false
    @State private var folderToDelete: Category? = nil
    @State private var showDeleteAlert    = false
    @State private var navigatedFolder: Category? = nil
    @State private var editableFolder: EditableFolderWrapper? = nil
    @State private var folderColorTick    = 0

    // MARK: - Environment

    @Environment(\.colorScheme) private var colorScheme
    @Environment(AppState.self) private var appState

    // MARK: - Layout

    private let columns = [
        GridItem(.flexible(), spacing: 14),
        GridItem(.flexible(), spacing: 14)
    ]

    // MARK: - Body

    var body: some View {
        if #available(iOS 26.0, *) {
            liquidGlassBody
        } else {
            legacyBody
        }
    }

    // MARK: - iOS 26+ Liquid Glass Navigation Bar

    @available(iOS 26.0, *)
    private var liquidGlassBody: some View {
        NavigationStack {
            ZStack {
                Design.Colors.background(for: colorScheme).ignoresSafeArea()

                if !isSearching && !viewModel.hasAnyFeeds {
                    VStack {
                        Spacer()
                        emptyStateView
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    mainContent
                }
            }
            .navigationTitle("Feeds")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 14) {
                        Button {
                            withAnimation(Design.Animation.standard) {
                                isSearching.toggle()
                                if !isSearching { searchText = "" }
                            }
                        } label: {
                            Image(systemName: isSearching ? "xmark.circle.fill" : "magnifyingglass")
                                .font(.system(size: 16, weight: .medium))
                        }

                        Button {
                            viewModel.showingAddFeed = true
                        } label: {
                            Image(systemName: "plus")
                                .font(.system(size: 16, weight: .semibold))
                        }
                    }
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                Color.clear.frame(height: 94)
            }
            .navigationDestination(item: $navigatedFolder) { folder in
                FolderDetailView(folder: folder)
            }
        }
        .sheet(isPresented: $viewModel.showingAddFeed) {
            AddFeedView()
        }
        .sheet(item: $editableFolder) { wrapper in
            EditFolderSheet(folder: wrapper.folder, viewModel: viewModel)
        }
        .alert("Delete Folder?", isPresented: $showDeleteAlert, presenting: folderToDelete) { folder in
            Button("Cancel", role: .cancel) { folderToDelete = nil }
            Button("Delete", role: .destructive) {
                withAnimation(Design.Animation.standard) {
                    viewModel.deleteFolder(folder)
                }
                folderToDelete = nil
            }
        } message: { folder in
            Text("Are you sure you want to delete \"\(folder.name)\"? All feeds inside will be moved to Unfiled.")
        }
        .animation(Design.Animation.standard, value: isSearching)
        .animation(Design.Animation.standard, value: viewModel.hasAnyFeeds)
    }

    // MARK: - Legacy Body (iOS 17-25)

    private var legacyBody: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                Design.Colors.background(for: colorScheme).ignoresSafeArea()

                if !isSearching && !viewModel.hasAnyFeeds {
                    VStack {
                        Spacer()
                        emptyStateView
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .safeAreaInset(edge: .top, spacing: 0) { legacyHeaderView }
                    .safeAreaInset(edge: .bottom, spacing: 0) { Color.clear.frame(height: 94) }
                } else {
                    mainContent
                        .safeAreaInset(edge: .top, spacing: 0) { legacyHeaderView }
                        .safeAreaInset(edge: .bottom, spacing: 0) { Color.clear.frame(height: 94) }
                }
            }
            .navigationDestination(item: $navigatedFolder) { folder in
                FolderDetailView(folder: folder)
            }
        }
        .sheet(isPresented: $viewModel.showingAddFeed) {
            AddFeedView()
        }
        .sheet(item: $editableFolder) { wrapper in
            EditFolderSheet(folder: wrapper.folder, viewModel: viewModel)
        }
        .alert("Delete Folder?", isPresented: $showDeleteAlert, presenting: folderToDelete) { folder in
            Button("Cancel", role: .cancel) { folderToDelete = nil }
            Button("Delete", role: .destructive) {
                withAnimation(Design.Animation.standard) {
                    viewModel.deleteFolder(folder)
                }
                folderToDelete = nil
            }
        } message: { folder in
            Text("Are you sure you want to delete \"\(folder.name)\"? All feeds inside will be moved to Unfiled.")
        }
        .animation(Design.Animation.standard, value: isSearching)
        .animation(Design.Animation.standard, value: viewModel.hasAnyFeeds)
    }

    // MARK: - Legacy Header (matches Discover/Settings)

    private var legacyHeaderView: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center) {
                Text("Feeds")
                    .font(Design.Typography.largeTitle)
                    .foregroundStyle(Design.Colors.primaryText(for: colorScheme))

                Spacer()

                HStack(spacing: 14) {
                    Button {
                        withAnimation(Design.Animation.standard) {
                            isSearching.toggle()
                            if !isSearching { searchText = "" }
                        }
                    } label: {
                        Image(systemName: isSearching ? "xmark.circle.fill" : "magnifyingglass")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(
                                isSearching
                                    ? Design.Colors.secondaryText(for: colorScheme)
                                    : Design.Colors.primaryText(for: colorScheme).opacity(0.85)
                            )
                    }
                    .buttonStyle(.plain)

                    Button {
                        viewModel.showingAddFeed = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Design.Colors.primary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, Design.Spacing.edge + 4)
            .padding(.top, 16)
            .padding(.bottom, isSearching ? 10 : Design.Spacing.edge)

            if isSearching {
                searchBar
                    .padding(.horizontal, Design.Spacing.edge + 4)
                    .padding(.bottom, 14)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .background(
            Rectangle()
                .fill(colorScheme == .dark ? .ultraThinMaterial : .regularMaterial)
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(Design.Colors.glassBorder(for: colorScheme))
                        .frame(height: 0.5)
                }
                .ignoresSafeArea(edges: .top)
        )
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Design.Colors.secondaryText(for: colorScheme))

            TextField("Search feeds...", text: $searchText)
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
    }

    // MARK: - Main Content

    private var mainContent: some View {
        ScrollView {
            VStack(spacing: 20) {
                if isSearching {
                    if #available(iOS 26.0, *) {
                        searchBar
                            .padding(.horizontal, Design.Spacing.edge)
                    }
                    searchResultsView
                } else {
                    folderGridView
                }
            }
            .padding(.top, 16)
        }
    }

    // MARK: - Folder Grid

    private var folderGridView: some View {
        // Reference folderColorTick so SwiftUI re-evaluates this subtree when
        // the user picks a new folder color from the palette inside a Menu.
        // (Menu presentation can otherwise suppress underlying re-renders.)
        let _ = folderColorTick

        return VStack(spacing: 14) {
            LazyVGrid(columns: columns, spacing: 14) {
                ForEach(viewModel.folders) { folder in
                    folderWidget(folder)
                }

                if !viewModel.unfiledFeeds.isEmpty {
                    unfiledWidget
                }
            }
            .padding(.horizontal, Design.Spacing.edge)
        }
    }

    // MARK: - Folder Widget

    private func folderWidget(_ folder: Category) -> some View {
        let feeds = viewModel.feeds(in: folder)

        return ZStack(alignment: .topTrailing) {
            // Main tappable area
            Button {
                navigatedFolder = folder
            } label: {
                VStack(spacing: 0) {
                    Spacer()

                    // Centered SF Symbol
                    Image(systemName: folder.icon)
                        .font(.system(size: 42, weight: .semibold))
                        .foregroundStyle(.white)

                    Spacer()

                    // Bottom-left title + feed count
                    VStack(alignment: .leading, spacing: 2) {
                        Text(folder.name)
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(.white)
                            .lineLimit(1)

                        Text("\(feeds.count) feed\(feeds.count == 1 ? "" : "s")")
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.7))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 14)
                }
                .frame(maxWidth: .infinity)
                .aspectRatio(1, contentMode: .fit)
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(
                            LinearGradient(
                                colors: [
                                    folder.color,
                                    folder.color.opacity(0.75)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .shadow(color: folder.color.opacity(0.3), radius: 10, y: 4)
                )
                .clipShape(RoundedRectangle(cornerRadius: 20))
            }
            .buttonStyle(.plain)

            // Three-dot context menu
            Menu {
                Button {
                    editableFolder = EditableFolderWrapper(folder)
                } label: {
                    Label("Edit", systemImage: "pencil")
                }

                Button(role: .destructive) {
                    folderToDelete = folder
                    showDeleteAlert = true
                } label: {
                    Label("Delete Folder", systemImage: "trash")
                }

                Picker("Color", selection: colorBinding(for: folder)) {
                    ForEach(folderColorHexOptions, id: \.self) { hex in
                        Label(hex, systemImage: "circle.fill")
                            .tint(Color(hex: hex))
                            .tag(hex)
                    }
                }
                .pickerStyle(.palette)
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white.opacity(0.9))
                    .frame(width: 30, height: 30)
                    .contentShape(Rectangle())
            }
            .padding(8)
        }
    }

    // MARK: - Unfiled Widget

    private var unfiledWidget: some View {
        let feeds = viewModel.unfiledFeeds

        return Button {
            let unfiledCategory = Category(
                id: SwiftDataService.unfiledFolderID,
                name: "Unfiled",
                icon: "tray",
                color: .gray,
                sortOrder: Int.max
            )
            navigatedFolder = unfiledCategory
        } label: {
            VStack(spacing: 0) {
                Spacer()

                Image(systemName: "tray")
                    .font(.system(size: 42, weight: .semibold))
                    .foregroundStyle(.white)

                Spacer()

                VStack(alignment: .leading, spacing: 2) {
                    Text("Unfiled")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    Text("\(feeds.count) feed\(feeds.count == 1 ? "" : "s")")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.7))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.bottom, 14)
            }
            .frame(maxWidth: .infinity)
            .aspectRatio(1, contentMode: .fit)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(
                        LinearGradient(
                            colors: [Color.gray, Color.gray.opacity(0.75)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .shadow(color: Color.gray.opacity(0.2), radius: 10, y: 4)
            )
            .clipShape(RoundedRectangle(cornerRadius: 20))
        }
        .buttonStyle(.plain)
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
                        ? "Type to search your feeds"
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
            .padding(.horizontal, Design.Spacing.edge)
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

            if feed.isPaywalled {
                Image(systemName: "lock.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(Design.Colors.secondaryText(for: colorScheme).opacity(0.6))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .contentShape(Rectangle())
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 28) {
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

    /// Creates a two-way binding that reads the folder's current color hex
    /// from the live data source and writes changes back through the view model.
    private func colorBinding(for folder: Category) -> Binding<String> {
        Binding<String>(
            get: {
                // Read from live data so the binding stays current after updates
                if let live = viewModel.folders.first(where: { $0.id == folder.id }) {
                    return EditFolderSheet.closestHex(for: live.color)
                }
                return EditFolderSheet.closestHex(for: folder.color)
            },
            set: { newHex in
                viewModel.updateFolder(folder, colorHex: newHex)
                folderColorTick &+= 1
            }
        )
    }

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

// MARK: - Edit Folder Sheet (Name + Icon)

struct EditFolderSheet: View {

    let folder: Category
    let viewModel: MyFeedsViewModel

    @State private var folderName: String
    @State private var selectedIcon: String

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    init(folder: Category, viewModel: MyFeedsViewModel) {
        self.folder = folder
        self.viewModel = viewModel
        _folderName = State(initialValue: folder.name)
        _selectedIcon = State(initialValue: folder.icon)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Preview
                    ZStack {
                        RoundedRectangle(cornerRadius: 20)
                            .fill(
                                LinearGradient(
                                    colors: [folder.color, folder.color.opacity(0.75)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 120, height: 120)

                        VStack(spacing: 8) {
                            Image(systemName: selectedIcon)
                                .font(.system(size: 36, weight: .semibold))
                                .foregroundStyle(.white)

                            Text(folderName.isEmpty ? "Folder" : folderName)
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                        }
                    }
                    .padding(.top, 8)

                    // Name
                    VStack(alignment: .leading, spacing: 8) {
                        Text("NAME")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Design.Colors.secondaryText(for: colorScheme))
                            .tracking(0.8)

                        TextField("Folder name", text: $folderName)
                            .font(.system(size: 16))
                            .foregroundStyle(Design.Colors.primaryText(for: colorScheme))
                            .tint(Design.Colors.primary)
                            .autocorrectionDisabled()
                            .padding()
                            .background(
                                RoundedRectangle(cornerRadius: Design.Radius.standard)
                                    .fill(Design.Colors.cardBackground(for: colorScheme))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: Design.Radius.standard)
                                            .stroke(Design.Colors.glassBorder(for: colorScheme), lineWidth: 0.5)
                                    )
                            )
                    }
                    .padding(.horizontal, Design.Spacing.edge)

                    // Icon
                    VStack(alignment: .leading, spacing: 8) {
                        Text("ICON")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Design.Colors.secondaryText(for: colorScheme))
                            .tracking(0.8)
                            .padding(.horizontal, Design.Spacing.edge)

                        let iconColumns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 5)
                        LazyVGrid(columns: iconColumns, spacing: 8) {
                            ForEach(folderIconOptions, id: \.self) { icon in
                                Button {
                                    selectedIcon = icon
                                } label: {
                                    let isSelected = selectedIcon == icon
                                    ZStack {
                                        RoundedRectangle(cornerRadius: 9)
                                            .fill(
                                                isSelected
                                                    ? folder.color.opacity(0.15)
                                                    : Design.Colors.cardBackground(for: colorScheme).opacity(0.6)
                                            )
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 9)
                                                    .stroke(
                                                        isSelected ? folder.color : Design.Colors.glassBorder(for: colorScheme),
                                                        lineWidth: isSelected ? 1.5 : 0.5
                                                    )
                                            )
                                        Image(systemName: icon)
                                            .font(.system(size: 18, weight: .medium))
                                            .foregroundStyle(
                                                isSelected
                                                    ? folder.color
                                                    : Design.Colors.secondaryText(for: colorScheme)
                                            )
                                    }
                                    .frame(height: 46)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, Design.Spacing.edge)
                    }
                }
                .padding(.top, Design.Spacing.section)
            }
            .background(Design.Colors.background(for: colorScheme))
            .navigationTitle("Edit Folder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Design.Colors.primary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let trimmed = folderName.trimmingCharacters(in: .whitespaces)
                        viewModel.updateFolder(
                            folder,
                            name: trimmed.isEmpty ? nil : trimmed,
                            iconName: selectedIcon
                        )
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .foregroundStyle(Design.Colors.primary)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(colorScheme == .dark ? .ultraThinMaterial : .regularMaterial)
        .presentationCornerRadius(Design.Radius.glass)
    }

    // Find closest hex from the color options for a given Color
    static func closestHex(for color: Color) -> String {
        let uiColor = UIColor(color)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        uiColor.getRed(&r, green: &g, blue: &b, alpha: &a)

        var bestHex = folderColorHexOptions[0]
        var bestDist: CGFloat = .greatestFiniteMagnitude

        for hex in folderColorHexOptions {
            let c = UIColor(Color(hex: hex))
            var cr: CGFloat = 0, cg: CGFloat = 0, cb: CGFloat = 0, ca: CGFloat = 0
            c.getRed(&cr, green: &cg, blue: &cb, alpha: &ca)
            let dist = (r - cr) * (r - cr) + (g - cg) * (g - cg) + (b - cb) * (b - cb)
            if dist < bestDist {
                bestDist = dist
                bestHex = hex
            }
        }
        return bestHex
    }
}

// MARK: - Preview

#Preview {
    MyFeedsView()
}
