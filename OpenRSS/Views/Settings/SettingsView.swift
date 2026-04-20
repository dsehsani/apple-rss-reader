//
//  SettingsView.swift
//  OpenRSS
//
//  Created by Darius Ehsani on 2/3/26.
//

import SwiftUI
import UniformTypeIdentifiers

/// Settings view with grouped preferences
struct SettingsView: View {

    // MARK: - State

    private var refreshStore = RefreshStateStore.shared
    @State private var userPrefs: UserPreferences? = nil
    @State private var notificationsEnabled: Bool = false

    // OPML
    @State private var isImporting = false
    @State private var showExportPicker = false
    @State private var exportItem: ExportFileItem? = nil
    @State private var opmlAlert: OPMLAlertItem? = nil

    // Account
    @State private var showAccountView: Bool = false
    private var authManager: AuthenticationManager { .shared }

    // MARK: - Environment (Light/Dark Mode)

    @Environment(\.colorScheme) private var colorScheme

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
            ScrollView {
                VStack(spacing: Design.Spacing.section) {
                    accountSection
                    appearanceSection
                    readingSection
                    affinitySection
                    dataSection
                    aboutSection
                }
                .padding(.top, Design.Spacing.edge)
            }
            .background(Design.Colors.background(for: colorScheme))
            .navigationTitle("Settings")
            .onAppear {
                userPrefs = SwiftDataService.shared.userPreferences()
            }
            .sheet(isPresented: $showAccountView) {
                AccountView()
            }
        }
    }

    // MARK: - Legacy Body (iOS 17–25)

    private var legacyBody: some View {
        ZStack(alignment: .top) {
            Design.Colors.background(for: colorScheme).ignoresSafeArea()

            ScrollView {
                VStack(spacing: Design.Spacing.section) {
                    accountSection
                    appearanceSection
                    readingSection
                    affinitySection
                    dataSection
                    aboutSection
                }
                .padding(.top, Design.Spacing.edge)
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                legacyHeaderView
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                Color.clear.frame(height: 94)
            }
            .onAppear {
                userPrefs = SwiftDataService.shared.userPreferences()
            }
            .sheet(isPresented: $showAccountView) {
                AccountView()
            }
        }
    }

    // MARK: - Legacy Header View

    private var legacyHeaderView: some View {
        Text("Settings")
            .font(Design.Typography.largeTitle)
            .foregroundStyle(Design.Colors.primaryText(for: colorScheme))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Design.Spacing.edge + 4)
            .padding(.top, 16)
            .padding(.bottom, Design.Spacing.edge)
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

    // MARK: - Account Section

    private var accountSection: some View {
        settingsSection(title: "Account", icon: "person.circle.fill") {
            Button {
                showAccountView = true
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: authManager.isSignedIn
                        ? "person.crop.circle.fill"
                        : "person.crop.circle.badge.plus")
                        .font(.system(size: 32))
                        .foregroundStyle(authManager.isSignedIn
                            ? Design.Colors.primary
                            : Design.Colors.secondaryText(for: colorScheme))

                    VStack(alignment: .leading, spacing: 2) {
                        if authManager.isSignedIn {
                            Text(authManager.currentUser?.displayName ?? "Apple ID User")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(Design.Colors.primaryText(for: colorScheme))
                            Text("iCloud sync available")
                                .font(.system(size: 13))
                                .foregroundStyle(Design.Colors.secondaryText(for: colorScheme))
                        } else {
                            Text("Sign In")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(Design.Colors.primaryText(for: colorScheme))
                            Text("Sync feeds across your devices")
                                .font(.system(size: 13))
                                .foregroundStyle(Design.Colors.secondaryText(for: colorScheme))
                        }
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Design.Colors.secondaryText(for: colorScheme).opacity(0.5))
                }
                .padding(.horizontal, Design.Spacing.edge)
                .padding(.vertical, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Appearance Section

    private var appearanceSection: some View {
        settingsSection(title: "Appearance", icon: "paintbrush.fill") {
            VStack(spacing: 0) {
                settingsRow(title: "App Icon", value: "Default")
                divider
                settingsRow(title: "Theme", value: "System")
                divider
                settingsToggle(title: "Show Article Images", isOn: Binding(
                    get: { userPrefs?.showImages ?? true },
                    set: { userPrefs?.showImages = $0 }
                ))
            }
        }
    }

    // MARK: - Reading Section

    private var readingSection: some View {
        settingsSection(title: "Reading", icon: "book.fill") {
            VStack(spacing: 0) {
                settingsToggle(title: "Open Links in App", isOn: Binding(
                    get: { userPrefs?.openLinksInApp ?? true },
                    set: { userPrefs?.openLinksInApp = $0 }
                ))
                divider
                settingsToggle(title: "Mark as Read on Scroll", isOn: Binding(
                    get: { userPrefs?.markAsReadOnScroll ?? false },
                    set: { userPrefs?.markAsReadOnScroll = $0 }
                ))
                divider
                settingsRow(title: "Text Size", value: "Medium")
            }
        }
    }

    // MARK: - Affinity Section (Phase 2d)

    private var affinitySection: some View {
        settingsSection(title: "Reading Signals", icon: "waveform.path.ecg") {
            VStack(spacing: 0) {
                NavigationLink {
                    SourceAffinityView()
                } label: {
                    HStack {
                        Text("Source Affinity")
                            .font(.system(size: 16))
                            .foregroundStyle(Design.Colors.primaryText(for: colorScheme))

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Design.Colors.secondaryText(for: colorScheme).opacity(0.5))
                    }
                    .padding(.horizontal, Design.Spacing.edge)
                    .padding(.vertical, 14)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Data Section

    private var dataSection: some View {
        settingsSection(title: "Data & Storage", icon: "externaldrive.fill") {
            VStack(spacing: 0) {
                settingsPicker(title: "Refresh Interval", selection: Binding(
                    get: { refreshStore.refreshInterval },
                    set: {
                        refreshStore.refreshInterval = $0
                        userPrefs?.refreshInterval = $0
                    }
                ))
                divider
                divider
                HStack {
                    Text("Last Updated")
                        .font(.system(size: 16))
                        .foregroundStyle(Design.Colors.primaryText(for: colorScheme))
                    Spacer()
                    Text(refreshStore.lastRefreshedString)
                        .font(.system(size: 16))
                        .foregroundStyle(Design.Colors.secondaryText(for: colorScheme))
                }
                .padding(.horizontal, Design.Spacing.edge)
                .padding(.vertical, 14)
                divider
                settingsToggle(title: "Cache Articles", isOn: Binding(
                    get: { userPrefs?.cacheEnabled ?? true },
                    set: { userPrefs?.cacheEnabled = $0 }
                ))
                divider
                settingsButton(title: "Clear Cache", subtitle: "124 MB", color: .red) {
                    // Clear cache action
                }
                divider
                settingsButton(title: "Export Subscriptions", subtitle: "OPML", color: .blue) {
                    showExportPicker = true
                }
                divider
                settingsButton(title: "Import Subscriptions", subtitle: "OPML", color: .green) {
                    isImporting = true
                }
            }
        }
        .sheet(isPresented: $showExportPicker) {
            OPMLExportPickerView { url in
                exportItem = ExportFileItem(url: url)
            }
        }
        .sheet(item: $exportItem) { item in
            ShareSheet(activityItems: [item.url])
        }
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: [.xml, .data],
            allowsMultipleSelection: false
        ) { result in
            handleImportResult(result)
        }
        .alert(item: $opmlAlert) { alert in
            Alert(
                title: Text(alert.title),
                message: Text(alert.message),
                dismissButton: .default(Text("OK"))
            )
        }
    }

    // MARK: - About Section

    private var aboutSection: some View {
        settingsSection(title: "About", icon: "info.circle.fill") {
            VStack(spacing: 0) {
                settingsRow(title: "Version", value: "1.0.0 (1)")
                divider
                settingsNavRow(title: "Privacy Policy")
                divider
                settingsNavRow(title: "Terms of Service")
                divider
                settingsNavRow(title: "Send Feedback")
            }
        }
    }

    // MARK: - Helper Views

    private func settingsSection<Content: View>(
        title: String,
        icon: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: Design.Spacing.small) {
            // Section header
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Design.Colors.primary)

                Text(title.uppercased())
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Design.Colors.secondaryText(for: colorScheme))
                    .tracking(0.5)
            }
            .padding(.horizontal, Design.Spacing.edge)

            // Content - adaptive background for light/dark mode
            content()
                .background(Design.Colors.cardBackground(for: colorScheme))
                .clipShape(RoundedRectangle(cornerRadius: Design.Radius.standard))
                .overlay(
                    RoundedRectangle(cornerRadius: Design.Radius.standard)
                        .stroke(
                            colorScheme == .dark
                                ? Design.Colors.subtleBorder
                                : Color.black.opacity(0.08),
                            lineWidth: 1
                        )
                )
                .padding(.horizontal, Design.Spacing.edge)
        }
    }

    private func settingsRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 16))
                .foregroundStyle(Design.Colors.primaryText(for: colorScheme))

            Spacer()

            Text(value)
                .font(.system(size: 16))
                .foregroundStyle(Design.Colors.secondaryText(for: colorScheme))

            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Design.Colors.secondaryText(for: colorScheme).opacity(0.5))
        }
        .padding(.horizontal, Design.Spacing.edge)
        .padding(.vertical, 14)
        .contentShape(Rectangle())
    }

    private func settingsNavRow(title: String) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 16))
                .foregroundStyle(Design.Colors.primaryText(for: colorScheme))

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Design.Colors.secondaryText(for: colorScheme).opacity(0.5))
        }
        .padding(.horizontal, Design.Spacing.edge)
        .padding(.vertical, 14)
        .contentShape(Rectangle())
    }

    private func settingsToggle(title: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            Text(title)
                .font(.system(size: 16))
                .foregroundStyle(Design.Colors.primaryText(for: colorScheme))
        }
        .tint(Design.Colors.primary)
        .padding(.horizontal, Design.Spacing.edge)
        .padding(.vertical, 10)
    }

    private func settingsPicker(title: String, selection: Binding<RefreshInterval>) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 16))
                .foregroundStyle(Design.Colors.primaryText(for: colorScheme))

            Spacer()

            Picker("", selection: selection) {
                ForEach(RefreshInterval.allCases, id: \.self) { interval in
                    Text(interval.rawValue).tag(interval)
                }
            }
            .tint(Design.Colors.primary)
        }
        .padding(.horizontal, Design.Spacing.edge)
        .padding(.vertical, 10)
    }

    private func settingsButton(title: String, subtitle: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .font(.system(size: 16))
                    .foregroundStyle(color)

                Spacer()

                Text(subtitle)
                    .font(.system(size: 14))
                    .foregroundStyle(Design.Colors.secondaryText)
            }
            .padding(.horizontal, Design.Spacing.edge)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var divider: some View {
        Rectangle()
            .fill(Design.Colors.subtleBorder)
            .frame(height: 1)
            .padding(.leading, Design.Spacing.edge)
    }

    // MARK: - OPML Import

    private func handleImportResult(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let error):
            opmlAlert = OPMLAlertItem(title: "Import Failed", message: error.localizedDescription)

        case .success(let urls):
            guard let url = urls.first else { return }
            do {
                let importResult = try OPMLService.shared.importFromURL(url, into: SwiftDataService.shared)
                opmlAlert = OPMLAlertItem(title: "Import Complete", message: importResult.summary)
            } catch {
                opmlAlert = OPMLAlertItem(title: "Import Failed", message: error.localizedDescription)
            }
        }
    }
}

// MARK: - Supporting Types

enum RefreshInterval: String, CaseIterable {
    case manual         = "Manual"
    case fifteenMinutes = "15 Minutes"
    case thirtyMinutes  = "30 Minutes"
    case hourly         = "Hourly"
    case daily          = "Daily"

    var intervalSeconds: TimeInterval {
        switch self {
        case .manual:         return .infinity
        case .fifteenMinutes: return 15 * 60
        case .thirtyMinutes:  return 30 * 60
        case .hourly:         return 60 * 60
        case .daily:          return 24 * 60 * 60
        }
    }
}

// MARK: - OPML Supporting Types

struct ExportFileItem: Identifiable {
    let id = UUID()
    let url: URL
}

struct OPMLAlertItem: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

// MARK: - Share Sheet

struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - OPML Export Picker

struct OPMLExportPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    let onExport: (URL) -> Void

    @State private var rows: [ExportRow] = []
    @State private var selectedIDs: Set<UUID> = []
    @State private var errorMessage: String? = nil

    private static let unfiledID = UUID(uuidString: "00000000-0000-0000-0000-FFFFFFFFFFFF")!

    var allSelected: Bool { selectedIDs.count == rows.count && !rows.isEmpty }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    // Select All row
                    selectAllRow
                        .padding(.top, 8)

                    Rectangle()
                        .fill(Design.Colors.subtleBorder)
                        .frame(height: 1)
                        .padding(.leading, Design.Spacing.edge)
                        .padding(.vertical, 4)

                    // Folder rows
                    ForEach(rows) { row in
                        folderRow(row)
                    }
                }
                .padding(.bottom, Design.Spacing.edge)
            }
            .background(Design.Colors.background(for: colorScheme))
            .navigationTitle("Export Subscriptions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Export") { performExport() }
                        .disabled(selectedIDs.isEmpty)
                        .bold()
                }
            }
            .onAppear { loadRows() }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Select All

    private var selectAllRow: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                if allSelected {
                    selectedIDs.removeAll()
                } else {
                    selectedIDs = Set(rows.map(\.id))
                }
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: allSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 24))
                    .foregroundStyle(allSelected ? Design.Colors.primary : Design.Colors.secondaryText(for: colorScheme).opacity(0.5))

                Text("Select All")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Design.Colors.primaryText(for: colorScheme))

                Spacer()

                Text("\(selectedIDs.count) of \(rows.count)")
                    .font(.system(size: 14))
                    .foregroundStyle(Design.Colors.secondaryText(for: colorScheme))
            }
            .padding(.horizontal, Design.Spacing.edge)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Folder Row

    private func folderRow(_ row: ExportRow) -> some View {
        let isSelected = selectedIDs.contains(row.id)

        return Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                if isSelected {
                    selectedIDs.remove(row.id)
                } else {
                    selectedIDs.insert(row.id)
                }
            }
        } label: {
            HStack(spacing: 12) {
                // Checkmark
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 24))
                    .foregroundStyle(isSelected ? Design.Colors.primary : Design.Colors.secondaryText(for: colorScheme).opacity(0.5))

                // Folder icon chip — matches CategorySectionHeader style
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(row.color.opacity(0.15))
                        .frame(width: 40, height: 40)

                    Image(systemName: row.icon)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(row.color)
                }

                // Folder name + feed count
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.name)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(Design.Colors.primaryText(for: colorScheme))

                    Text("\(row.feedCount) feed\(row.feedCount == 1 ? "" : "s")")
                        .font(.system(size: 13))
                        .foregroundStyle(Design.Colors.secondaryText(for: colorScheme))
                }

                Spacer()
            }
            .padding(.horizontal, Design.Spacing.edge)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Data Loading

    private func loadRows() {
        let service = SwiftDataService.shared
        let folders = service.allFolderModels()
        let categories = service.categories
        let unfiled = service.unfiledFeedModels()

        var result: [ExportRow] = folders.compactMap { folder in
            let count = folder.feeds.count
            guard count > 0 else { return nil }

            // Look up icon + color from the Category domain model
            let cat = categories.first { $0.id == folder.id }
            return ExportRow(
                id: folder.id,
                name: folder.name,
                feedCount: count,
                icon: cat?.icon ?? folder.iconName,
                color: cat?.color ?? Color(hex: folder.colorHex)
            )
        }

        if !unfiled.isEmpty {
            result.append(ExportRow(
                id: Self.unfiledID,
                name: "Unfiled",
                feedCount: unfiled.count,
                icon: "tray",
                color: .gray
            ))
        }

        rows = result
        selectedIDs = Set(result.map(\.id))
    }

    // MARK: - Export

    private func performExport() {
        let service = SwiftDataService.shared
        let allFolders = service.allFolderModels()
        let allUnfiled = service.unfiledFeedModels()

        let selectedFolders = allFolders.filter { selectedIDs.contains($0.id) }
        let selectedUnfiled = selectedIDs.contains(Self.unfiledID) ? allUnfiled : []

        do {
            let url = try OPMLService.shared.export(folders: selectedFolders, unfiledFeeds: selectedUnfiled)
            dismiss()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                onExport(url)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct ExportRow: Identifiable {
    let id: UUID
    let name: String
    let feedCount: Int
    let icon: String
    let color: Color
}

// MARK: - Preview

#Preview {
    SettingsView()
}
