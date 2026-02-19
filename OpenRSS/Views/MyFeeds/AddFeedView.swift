//
//  AddFeedView.swift
//  OpenRSS
//
//  Glass bottom sheet for subscribing to a new RSS feed.
//
//  Flow:
//    1. User types a URL and taps the arrow → feed title auto-fetches
//    2. Feed name field appears (pre-filled, editable)
//    3. Folder picker appears (existing folders + inline "New Folder" option)
//       → New Folder expands a name field + color swatches + icon grid
//    4. Tap "Subscribe" → saves to SwiftData and dismisses
//

import SwiftUI

// MARK: - Folder Appearance Options

private let folderColorHexes: [String] = [
    "007AFF", "FF9500", "34C759", "AF52DE", "FF2D55",
    "5AC8FA", "FF3B30", "5856D0", "FFCC00", "00C7BE"
]

private let folderIcons: [String] = [
    "folder.fill",        "star.fill",      "heart.fill",    "bookmark.fill",
    "newspaper.fill",     "laptopcomputer", "gamecontroller.fill", "music.note",
    "camera.fill",        "cart.fill",      "globe",         "leaf.fill",
    "flame.fill",         "bolt.fill",      "person.fill",   "airplane"
]

// MARK: - AddFeedView

struct AddFeedView: View {

    // MARK: - ViewModel

    @State private var viewModel = AddFeedViewModel()

    // MARK: - Environment

    @Environment(\.dismiss)     private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ZStack {
                Design.Colors.background(for: colorScheme).ignoresSafeArea()

                ScrollView {
                    VStack(spacing: Design.Spacing.section) {
                        urlInputSection

                        // These sections slide in after a successful fetch
                        if viewModel.hasFetchedSuccessfully {
                            feedNameSection
                                .transition(.move(edge: .top).combined(with: .opacity))
                            folderPickerSection
                                .transition(.move(edge: .top).combined(with: .opacity))
                        }

                        // Error messages
                        if let error = viewModel.fetchError ?? viewModel.saveError {
                            Text(error)
                                .font(.system(size: 14))
                                .foregroundStyle(.red)
                                .padding(.horizontal, Design.Spacing.edge)
                        }

                        Spacer(minLength: 40)
                    }
                    .padding(.top, Design.Spacing.section)
                    .animation(Design.Animation.standard, value: viewModel.hasFetchedSuccessfully)
                }
            }
            .navigationTitle("Add Feed")
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
                            .foregroundStyle(
                                viewModel.canSubscribe
                                    ? Design.Colors.primary
                                    : Design.Colors.secondaryText(for: colorScheme)
                            )
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
        .onDisappear { viewModel.reset() }
    }

    // MARK: - URL Input Section

    private var urlInputSection: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.small) {
            sectionLabel("FEED URL")

            HStack(spacing: 10) {
                TextField("https://example.com/feed.xml", text: $viewModel.urlText)
                    .font(.system(size: 16))
                    .foregroundStyle(Design.Colors.primaryText(for: colorScheme))
                    .tint(Design.Colors.primary)
                    .autocorrectionDisabled()
                    .autocapitalization(.none)
                    .keyboardType(.URL)
                    .submitLabel(.go)
                    .onSubmit { Task { await viewModel.fetchFeedTitle() } }

                // Fetch button / status indicator
                Button {
                    Task { await viewModel.fetchFeedTitle() }
                } label: {
                    if viewModel.isFetching {
                        ProgressView().controlSize(.small)
                            .frame(width: 28, height: 28)
                    } else {
                        Image(
                            systemName: viewModel.hasFetchedSuccessfully
                                ? "checkmark.circle.fill"
                                : "arrow.right.circle.fill"
                        )
                        .font(.system(size: 26))
                        .foregroundStyle(
                            viewModel.hasFetchedSuccessfully ? .green : Design.Colors.primary
                        )
                    }
                }
                .buttonStyle(.plain)
                .disabled(viewModel.isFetching || viewModel.urlText.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding()
            .background(cardBackground)
        }
        .padding(.horizontal, Design.Spacing.edge)
    }

    // MARK: - Feed Name Section

    private var feedNameSection: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.small) {
            sectionLabel("FEED NAME")

            TextField("Feed name", text: $viewModel.fetchedTitle)
                .font(.system(size: 16))
                .foregroundStyle(Design.Colors.primaryText(for: colorScheme))
                .tint(Design.Colors.primary)
                .padding()
                .background(cardBackground)
        }
        .padding(.horizontal, Design.Spacing.edge)
    }

    // MARK: - Folder Picker Section

    private var folderPickerSection: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.small) {
            sectionLabel("FOLDER")

            VStack(spacing: 0) {
                // "No Folder" option
                folderRow(id: nil, name: "No Folder", icon: "tray", color: .gray)

                // Existing folders
                ForEach(viewModel.availableFolders) { folder in
                    dividerLine
                    folderRow(id: folder.id, name: folder.name, icon: folder.icon, color: folder.color)
                }

                // Inline "New Folder" creation
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

                // Selected checkmark
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

    // MARK: - New Folder Row (with color + icon picker)

    private var newFolderRow: some View {
        VStack(spacing: 0) {
            if viewModel.isCreatingNewFolder {
                // Folder preview chip + inline name field (exactly where the name label sits)
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

                // Color picker
                dividerLine
                folderColorPicker
                    .transition(.move(edge: .top).combined(with: .opacity))

                // Icon picker
                dividerLine
                folderIconPicker
                    .transition(.move(edge: .top).combined(with: .opacity))
            } else {
                // Collapsed: tap to begin creating a new folder
                Button {
                    withAnimation(Design.Animation.standard) {
                        viewModel.isCreatingNewFolder = true
                        viewModel.selectedFolderID = nil
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
                    ForEach(folderColorHexes, id: \.self) { hex in
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
                                Circle()
                                    .stroke(
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
                ForEach(folderIcons, id: \.self) { icon in
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
                                            isSelected ? selectedColor : Design.Colors.glassBorder(for: colorScheme),
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
        Divider()
            .background(Design.Colors.glassBorder(for: colorScheme))
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

// MARK: - Preview

#Preview {
    Color.clear
        .sheet(isPresented: .constant(true)) {
            AddFeedView()
        }
}
