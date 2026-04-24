//
//  QuickAddFeedSheet.swift
//  OpenRSS
//
//  Streamlined "Add to Feeds" sheet for feeds already known from the catalog.
//  Skips the URL-fetch step — the feed URL and title are pre-populated.
//  The user just picks (or creates) a folder and taps Subscribe.
//

import SwiftUI

// MARK: - QuickAddViewModel

@Observable
@MainActor
final class QuickAddViewModel {

    // MARK: Source feed

    let feed: CatalogFeed

    // MARK: Folder State

    var selectedFolderID: UUID? = nil
    var isCreatingNewFolder: Bool = false
    var newFolderName: String = ""
    var newFolderIcon: String = "folder.fill"
    var newFolderColorHex: String = "007AFF"

    // MARK: Save State

    var isSaving: Bool = false
    var saveError: String? = nil

    // MARK: Computed

    var availableFolders: [Category] { SwiftDataService.shared.categories }
    var canSubscribe: Bool { !isSaving }

    // MARK: Init

    init(feed: CatalogFeed) {
        self.feed = feed
    }

    // MARK: Subscribe

    func subscribe(dismiss: () -> Void) async {
        isSaving = true
        saveError = nil

        do {
            var folderID = selectedFolderID
            if isCreatingNewFolder {
                let name = newFolderName.trimmingCharacters(in: .whitespaces)
                guard !name.isEmpty else {
                    saveError = "Please enter a folder name."
                    isSaving = false
                    return
                }
                try SwiftDataService.shared.addFolder(
                    name: name,
                    iconName: newFolderIcon,
                    colorHex: newFolderColorHex
                )
                folderID = SwiftDataService.shared.categories.last?.id
            }

            try SwiftDataService.shared.addFeed(
                feedURL:    feed.feedURL,
                title:      feed.name,
                websiteURL: feed.websiteURL,
                folderID:   folderID
            )
            dismiss()
        } catch {
            saveError = "Failed to save: \(error.localizedDescription)"
        }

        isSaving = false
    }
}

// MARK: - QuickAddFeedSheet

struct QuickAddFeedSheet: View {

    let feed: CatalogFeed

    @State private var viewModel: QuickAddViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    init(feed: CatalogFeed) {
        self.feed = feed
        self._viewModel = State(initialValue: QuickAddViewModel(feed: feed))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Design.Colors.background(for: colorScheme).ignoresSafeArea()

                ScrollView {
                    VStack(spacing: Design.Spacing.section) {
                        feedHeaderSection
                        folderPickerSection

                        if let error = viewModel.saveError {
                            Text(error)
                                .font(.system(size: 14))
                                .foregroundStyle(.red)
                                .padding(.horizontal, Design.Spacing.edge)
                        }

                        Spacer(minLength: 40)
                    }
                    .padding(.top, Design.Spacing.section)
                }
            }
            .navigationTitle("Add to Feeds")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Design.Colors.primary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Group {
                        if viewModel.isSaving {
                            ProgressView().controlSize(.small)
                        } else {
                            Button("Subscribe") {
                                Task { await viewModel.subscribe { dismiss() } }
                            }
                            .fontWeight(.semibold)
                            .foregroundStyle(Design.Colors.primary)
                            .disabled(!viewModel.canSubscribe)
                        }
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(colorScheme == .dark ? .ultraThinMaterial : .regularMaterial)
        .presentationCornerRadius(Design.Radius.glass)
    }

    // MARK: - Feed Header

    private var feedHeaderSection: some View {
        HStack(spacing: 14) {
            // Icon using catalog category color/icon if available
            let cat = RSSCatalog.category(for: feed)
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill((cat?.color ?? Design.Colors.primary).opacity(0.12))
                    .frame(width: 56, height: 56)
                Image(systemName: cat?.icon ?? "dot.radiowaves.left.and.right")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(cat?.color ?? Design.Colors.primary)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(feed.name)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Design.Colors.primaryText(for: colorScheme))

                Text(feed.description)
                    .font(.system(size: 14))
                    .foregroundStyle(Design.Colors.secondaryText)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Design.Spacing.edge)
    }

    // MARK: - Folder Picker

    private var folderPickerSection: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.small) {
            sectionLabel("FOLDER")

            VStack(spacing: 0) {
                folderRow(id: nil, name: "No Folder", icon: "tray", color: .gray)

                ForEach(viewModel.availableFolders) { folder in
                    dividerLine
                    folderRow(id: folder.id, name: folder.name, icon: folder.icon, color: folder.color)
                }

                dividerLine
                newFolderRow
            }
            .background(cardBackground)
        }
        .padding(.horizontal, Design.Spacing.edge)
    }

    private func folderRow(id: UUID?, name: String, icon: String, color: Color) -> some View {
        Button {
            viewModel.selectedFolderID    = id
            viewModel.isCreatingNewFolder = false
        } label: {
            HStack(spacing: 12) {
                iconChip(icon: icon, color: color)

                Text(name)
                    .font(.system(size: 16))
                    .foregroundStyle(Design.Colors.primaryText(for: colorScheme))

                Spacer()

                if !viewModel.isCreatingNewFolder && viewModel.selectedFolderID == id {
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Design.Colors.primary)
                }
            }
            .padding(.horizontal, Design.Spacing.edge)
            .padding(.vertical, 13)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var newFolderRow: some View {
        VStack(spacing: 0) {
            if viewModel.isCreatingNewFolder {
                HStack(spacing: 12) {
                    iconChip(
                        icon: viewModel.newFolderIcon,
                        color: Color(hex: viewModel.newFolderColorHex)
                    )

                    TextField("Folder name", text: $viewModel.newFolderName)
                        .font(.system(size: 16))
                        .foregroundStyle(Design.Colors.primaryText(for: colorScheme))
                        .tint(Design.Colors.primary)
                        .autocorrectionDisabled()

                    Spacer()

                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Design.Colors.primary)
                }
                .padding(.horizontal, Design.Spacing.edge)
                .padding(.vertical, 13)

                dividerLine
                folderColorPicker
                    .transition(.move(edge: .top).combined(with: .opacity))

                dividerLine
                folderIconPicker
                    .transition(.move(edge: .top).combined(with: .opacity))

            } else {
                Button {
                    withAnimation(Design.Animation.standard) {
                        viewModel.isCreatingNewFolder = true
                        viewModel.selectedFolderID    = nil
                    }
                } label: {
                    HStack(spacing: 12) {
                        iconChip(icon: "folder.badge.plus", color: Design.Colors.primary)

                        Text("New Folder…")
                            .font(.system(size: 16))
                            .foregroundStyle(Design.Colors.primary)

                        Spacer()
                    }
                    .padding(.horizontal, Design.Spacing.edge)
                    .padding(.vertical, 13)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .animation(Design.Animation.standard, value: viewModel.isCreatingNewFolder)
    }

    // MARK: - Color Picker

    private var folderColorPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("COLOR")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Design.Colors.secondaryText(for: colorScheme))
                .tracking(0.8)
                .padding(.horizontal, Design.Spacing.edge)
                .padding(.top, 10)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(quickAddFolderColorHexes, id: \.self) { hex in
                        Button {
                            viewModel.newFolderColorHex = hex
                        } label: {
                            let isSelected = viewModel.newFolderColorHex == hex
                            ZStack {
                                Circle()
                                    .fill(Color(hex: hex))
                                    .frame(width: 30, height: 30)
                                if isSelected {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 12, weight: .bold))
                                        .foregroundStyle(.white)
                                }
                            }
                            .padding(3)
                            .background(
                                Circle().stroke(
                                    isSelected ? Color(hex: hex) : Color.clear,
                                    lineWidth: 2
                                )
                            )
                        }
                        .buttonStyle(.plain)
                        .animation(Design.Animation.quick, value: viewModel.newFolderColorHex)
                    }
                }
                .padding(.horizontal, Design.Spacing.edge)
            }
            .padding(.bottom, 10)
        }
    }

    // MARK: - Icon Picker

    private var folderIconPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("ICON")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Design.Colors.secondaryText(for: colorScheme))
                .tracking(0.8)
                .padding(.horizontal, Design.Spacing.edge)
                .padding(.top, 10)

            let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 5)
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(quickAddFolderIcons, id: \.self) { icon in
                    Button {
                        viewModel.newFolderIcon = icon
                    } label: {
                        let selectedColor = Color(hex: viewModel.newFolderColorHex)
                        let isSelected    = viewModel.newFolderIcon == icon
                        ZStack {
                            RoundedRectangle(cornerRadius: 9)
                                .fill(
                                    isSelected
                                        ? selectedColor.opacity(0.15)
                                        : Design.Colors.cardBackground(for: colorScheme).opacity(0.6)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 9)
                                        .stroke(
                                            isSelected
                                                ? selectedColor
                                                : Design.Colors.glassBorder(for: colorScheme),
                                            lineWidth: isSelected ? 1.5 : 0.5
                                        )
                                )
                            Image(systemName: icon)
                                .font(.system(size: 18, weight: .medium))
                                .foregroundStyle(
                                    isSelected
                                        ? selectedColor
                                        : Design.Colors.secondaryText(for: colorScheme)
                                )
                        }
                        .frame(height: 46)
                    }
                    .buttonStyle(.plain)
                    .animation(Design.Animation.quick, value: viewModel.newFolderIcon)
                }
            }
            .padding(.horizontal, Design.Spacing.edge)
            .padding(.bottom, 12)
        }
    }

    // MARK: - Helpers

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Design.Colors.secondaryText(for: colorScheme))
            .tracking(0.8)
    }

    private func iconChip(icon: String, color: Color) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 7)
                .fill(color.opacity(0.15))
                .frame(width: 32, height: 32)
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(color)
        }
    }

    private var dividerLine: some View {
        Divider().background(Design.Colors.glassBorder(for: colorScheme))
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: Design.Radius.standard)
            .fill(Design.Colors.cardBackground(for: colorScheme))
            .overlay(
                RoundedRectangle(cornerRadius: Design.Radius.standard)
                    .stroke(Design.Colors.glassBorder(for: colorScheme), lineWidth: 0.5)
            )
    }
}

// MARK: - Constants

private let quickAddFolderColorHexes: [String] = [
    "007AFF", "FF9500", "34C759", "AF52DE", "FF2D55",
    "5AC8FA", "FF3B30", "5856D0", "FFCC00", "00C7BE"
]

private let quickAddFolderIcons: [String] = [
    "folder.fill",        "star.fill",           "heart.fill",          "bookmark.fill",
    "newspaper.fill",     "laptopcomputer",       "gamecontroller.fill", "music.note",
    "camera.fill",        "cart.fill",            "globe",               "leaf.fill",
    "flame.fill",         "bolt.fill",            "person.fill",         "airplane"
]

// MARK: - Preview

#Preview {
    Color.clear
        .sheet(isPresented: .constant(true)) {
            QuickAddFeedSheet(feed: CatalogFeed(
                name: "Hacker News",
                feedURL: "https://news.ycombinator.com/rss",
                description: "Links for the intellectually curious, ranked by readers."
            ))
        }
}
