//
//  SavedView.swift
//  OpenRSS
//
//  Created by Darius Ehsani on 2/3/26.
//

import SwiftUI

/// Saved/bookmarked articles view
struct SavedView: View {

    // MARK: - ViewModel

    @State private var viewModel = SavedViewModel()

    // MARK: - Environment (Light/Dark Mode)

    @Environment(\.colorScheme) private var colorScheme

    // MARK: - Body

    var body: some View {
        ZStack(alignment: .top) {
            // Background - adaptive for light/dark mode
            Design.Colors.background(for: colorScheme).ignoresSafeArea()

            // Main content
            ScrollView {
                LazyVStack(spacing: Design.Spacing.cardGap) {
                    // Spacer for header
                    Color.clear.frame(height: 130)

                    // Empty state or articles
                    if viewModel.filteredArticles.isEmpty {
                        emptyState
                    } else {
                        ForEach(viewModel.filteredArticles) { article in
                            ArticleCardView(
                                article: article,
                                source: viewModel.source(for: article),
                                onBookmarkTap: {
                                    viewModel.toggleBookmark(for: article)
                                },
                                onShareTap: {
                                    // Share action
                                },
                                onReadMoreTap: {
                                    viewModel.markAsRead(article)
                                }
                            )
                            .padding(.horizontal, Design.Spacing.edge)
                        }
                    }

                    // Bottom padding for tab bar
                    Color.clear.frame(height: 100)
                }
            }

            // Sticky header
            headerView
        }
        .sheet(isPresented: $viewModel.showingFilterSheet) {
            sortOptionsSheet
        }
    }

    // MARK: - Header View

    private var headerView: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Saved")
                        .font(Design.Typography.largeTitle)
                        .foregroundStyle(Design.Colors.primaryText(for: colorScheme))

                    if viewModel.savedCount > 0 {
                        Text("\(viewModel.savedCount) articles • \(viewModel.unreadSavedCount) unread")
                            .font(.system(size: 14))
                            .foregroundStyle(Design.Colors.secondaryText(for: colorScheme))
                    }
                }

                Spacer()

                // Sort button
                Button {
                    viewModel.showingFilterSheet = true
                } label: {
                    HStack(spacing: 4) {
                        Text(viewModel.sortOption.rawValue)
                            .font(.system(size: 14, weight: .medium))
                        Image(systemName: "chevron.down")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundStyle(Design.Colors.primary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Design.Colors.primary.opacity(0.1))
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, Design.Spacing.edge)
            .padding(.top, 60)
            .padding(.bottom, Design.Spacing.edge)
        }
        .background(
            Rectangle()
                .fill(colorScheme == .dark ? .ultraThinMaterial : .regularMaterial)
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(Design.Colors.glassBorder(for: colorScheme))
                        .frame(height: 0.5)
                }
                .ignoresSafeArea()
        )
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: Design.Spacing.edge) {
            Image(systemName: "bookmark")
                .font(.system(size: 64, weight: .light))
                .foregroundStyle(Design.Colors.secondaryText(for: colorScheme).opacity(0.5))

            Text("No Saved Articles")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Design.Colors.primaryText(for: colorScheme))

            Text("Articles you bookmark will appear here")
                .font(.system(size: 16))
                .foregroundStyle(Design.Colors.secondaryText(for: colorScheme))
                .multilineTextAlignment(.center)
        }
        .padding(.top, 100)
        .padding(.horizontal, Design.Spacing.section)
    }

    // MARK: - Sort Options Sheet

    private var sortOptionsSheet: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                VStack(spacing: 0) {
                    ForEach(SavedSortOption.allCases, id: \.self) { option in
                        Button {
                            viewModel.setSortOption(option)
                            viewModel.showingFilterSheet = false
                        } label: {
                            HStack {
                                Text(option.rawValue)
                                    .font(.system(size: 17))
                                    .foregroundStyle(.white)

                                Spacer()

                                if viewModel.sortOption == option {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundStyle(Design.Colors.primary)
                                }
                            }
                            .padding(.horizontal, Design.Spacing.edge)
                            .padding(.vertical, 16)
                            .background(Design.Colors.cardBackground.opacity(0.5))
                        }
                        .buttonStyle(.plain)

                        Rectangle()
                            .fill(Design.Colors.subtleBorder)
                            .frame(height: 1)
                    }

                    Spacer()
                }
                .padding(.top, Design.Spacing.edge)
            }
            .navigationTitle("Sort By")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        viewModel.showingFilterSheet = false
                    }
                    .foregroundStyle(Design.Colors.primary)
                }
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }
}

// MARK: - Preview

#Preview {
    SavedView()
}
