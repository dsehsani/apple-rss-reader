//
//  SourcesView.swift
//  OpenRSS
//
//  Created by Darius Ehsani on 2/3/26.
//

import SwiftUI

/// Sources management view with expandable category sections
struct SourcesView: View {

    // MARK: - ViewModel

    @State private var viewModel = SourcesViewModel()

    // MARK: - Environment (Light/Dark Mode)

    @Environment(\.colorScheme) private var colorScheme

    // MARK: - Body

    var body: some View {
        ZStack(alignment: .top) {
            // Background - adaptive for light/dark mode
            Design.Colors.background(for: colorScheme).ignoresSafeArea()

            // Main content — safeAreaInset adapts to any device automatically
            ScrollView {
                LazyVStack(spacing: 0) {
                    // Search bar
                    searchBar
                        .padding(.horizontal, Design.Spacing.edge)
                        .padding(.top, Design.Spacing.edge)
                        .padding(.bottom, Design.Spacing.edge)

                    // Category sections
                    ForEach(viewModel.filteredCategories) { category in
                        VStack(spacing: 0) {
                            // Category header
                            CategorySectionHeader(
                                category: category,
                                sourceCount: viewModel.sourceCount(for: category),
                                unreadCount: viewModel.unreadCount(for: category),
                                isExpanded: viewModel.isExpanded(category)
                            ) {
                                viewModel.toggleExpansion(for: category)
                            }

                            // Sources (if expanded)
                            if viewModel.isExpanded(category) {
                                ForEach(viewModel.filteredSources(for: category)) { source in
                                    SourceRowView(
                                        source: source,
                                        unreadCount: viewModel.unreadCount(for: source)
                                    )
                                    .background(Design.Colors.cardBackground.opacity(0.3))
                                }
                            }

                            // Divider
                            Rectangle()
                                .fill(Design.Colors.subtleBorder)
                                .frame(height: 1)
                        }
                    }

                    // Manage Categories button
                    manageCategoriesButton
                        .padding(Design.Spacing.edge)
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                headerView
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                Color.clear.frame(height: 94)
            }

            // Floating add button
            addButton
        }
        .sheet(isPresented: $viewModel.showingAddSourceSheet) {
            addSourceSheet
        }
    }

    // MARK: - Header View
    // .ignoresSafeArea(edges: .top) lets the material fill up to the Dynamic Island / notch.

    private var headerView: some View {
        Text("Sources")
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

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: Design.Icons.search)
                .font(.system(size: 16))
                .foregroundStyle(Design.Colors.secondaryText(for: colorScheme))

            TextField("Search sources...", text: $viewModel.searchText)
                .font(.system(size: 16))
                .foregroundStyle(Design.Colors.primaryText(for: colorScheme))
                .tint(Design.Colors.primary)

            if !viewModel.searchText.isEmpty {
                Button {
                    viewModel.searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(Design.Colors.secondaryText(for: colorScheme))
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
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
    }

    // MARK: - Manage Categories Button

    private var manageCategoriesButton: some View {
        Button {
            viewModel.showManageCategories()
        } label: {
            HStack {
                Image(systemName: "folder.badge.gearshape")
                    .font(.system(size: 16, weight: .medium))
                Text("Manage Categories")
                    .font(.system(size: 16, weight: .medium))
            }
            .foregroundStyle(Design.Colors.primary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Design.Colors.primary.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: Design.Radius.standard))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Floating Add Button

    private var addButton: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                Button {
                    viewModel.showAddSource()
                } label: {
                    Image(systemName: Design.Icons.add)
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 56, height: 56)
                        .background(Design.Colors.primary)
                        .clipShape(Circle())
                        .shadow(color: Design.Colors.primary.opacity(0.4), radius: 8, y: 4)
                }
                .buttonStyle(.plain)
                .padding(.trailing, Design.Spacing.edge)
                .padding(.bottom, 100)
            }
        }
    }

    // MARK: - Add Source Sheet

    private var addSourceSheet: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                VStack(spacing: Design.Spacing.section) {
                    Text("Add a new RSS feed by entering its URL")
                        .font(.system(size: 16))
                        .foregroundStyle(Design.Colors.secondaryText)
                        .multilineTextAlignment(.center)
                        .padding(.top, Design.Spacing.section)

                    // URL input field
                    TextField("Feed URL", text: .constant(""))
                        .font(.system(size: 16))
                        .foregroundStyle(.white)
                        .tint(Design.Colors.primary)
                        .padding()
                        .background(Design.Colors.cardBackground)
                        .clipShape(RoundedRectangle(cornerRadius: Design.Radius.standard))
                        .overlay(
                            RoundedRectangle(cornerRadius: Design.Radius.standard)
                                .stroke(Design.Colors.subtleBorder, lineWidth: 1)
                        )
                        .padding(.horizontal, Design.Spacing.edge)

                    Spacer()
                }
            }
            .navigationTitle("Add Source")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        viewModel.showingAddSourceSheet = false
                    }
                    .foregroundStyle(Design.Colors.primary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        viewModel.showingAddSourceSheet = false
                    }
                    .foregroundStyle(Design.Colors.primary)
                    .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }
}

// MARK: - Preview

#Preview {
    SourcesView()
}
