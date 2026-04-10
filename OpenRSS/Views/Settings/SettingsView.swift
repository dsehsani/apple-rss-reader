//
//  SettingsView.swift
//  OpenRSS
//
//  Created by Darius Ehsani on 2/3/26.
//

import SwiftUI

/// Settings view with grouped preferences
struct SettingsView: View {

    // MARK: - State

    @State private var refreshInterval: RefreshInterval = .hourly
    @State private var showImages: Bool = true
    @State private var openLinksInApp: Bool = true
    @State private var markAsReadOnScroll: Bool = false
    @State private var cacheEnabled: Bool = true
    @State private var notificationsEnabled: Bool = false
    @State private var showAccountView: Bool = false

    // MARK: - Auth

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
                    dataSection
                    aboutSection
                }
                .padding(.top, Design.Spacing.edge)
            }
            .background(Design.Colors.background(for: colorScheme))
            .navigationTitle("Settings")
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
        }
        .sheet(isPresented: $showAccountView) {
            AccountView()
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
                    // Avatar
                    Image(systemName: authManager.isSignedIn ? "person.crop.circle.fill" : "person.crop.circle.badge.plus")
                        .font(.system(size: 32))
                        .foregroundStyle(authManager.isSignedIn ? Design.Colors.primary : Design.Colors.secondaryText(for: colorScheme))

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
                settingsToggle(title: "Show Article Images", isOn: $showImages)
            }
        }
    }

    // MARK: - Reading Section

    private var readingSection: some View {
        settingsSection(title: "Reading", icon: "book.fill") {
            VStack(spacing: 0) {
                settingsToggle(title: "Open Links in App", isOn: $openLinksInApp)
                divider
                settingsToggle(title: "Mark as Read on Scroll", isOn: $markAsReadOnScroll)
                divider
                settingsRow(title: "Text Size", value: "Medium")
            }
        }
    }

    // MARK: - Data Section

    private var dataSection: some View {
        settingsSection(title: "Data & Storage", icon: "externaldrive.fill") {
            VStack(spacing: 0) {
                settingsPicker(title: "Refresh Interval", selection: $refreshInterval)
                divider
                settingsToggle(title: "Cache Articles", isOn: $cacheEnabled)
                divider
                settingsButton(title: "Clear Cache", subtitle: "124 MB", color: .red) {
                    // Clear cache action
                }
            }
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
}

// MARK: - Supporting Types

enum RefreshInterval: String, CaseIterable {
    case manual = "Manual"
    case fifteenMinutes = "15 Minutes"
    case thirtyMinutes = "30 Minutes"
    case hourly = "Hourly"
    case daily = "Daily"
}

// MARK: - Preview

#Preview {
    SettingsView()
}
