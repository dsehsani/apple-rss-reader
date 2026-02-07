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
                    // Spacer for header - reduced to match new header positioning
                    Color.clear.frame(height: 140)

                    // Articles
                    ForEach(viewModel.filteredArticles) { article in
                        ArticleCardView(
                            article: article,
                            source: viewModel.source(for: article),
                            onBookmarkTap: {
                                viewModel.toggleBookmark(for: article)
                            },
                            onShareTap: {
                                shareArticle(article)
                            },
                            onReadMoreTap: {
                                viewModel.markAsRead(article)
                            }
                        )
                        .padding(.horizontal, Design.Spacing.edge)
                    }

                    // Bottom padding for tab bar
                    Color.clear.frame(height: 100)
                }
            }
            .refreshable {
                await viewModel.refresh()
            }

            // Floating glass header
            floatingGlassHeader
        }
    }

    // MARK: - Floating Glass Header

    private var floatingGlassHeader: some View {
        VStack(spacing: 0) {
            // Glass container - positioned closer to status bar
            VStack(spacing: 12) {
                // Title row with controls
                HStack(alignment: .center) {
                    // Title on left - adaptive text color
                    Text("Today")
                        .font(Design.Typography.largeTitle)
                        .foregroundStyle(Design.Colors.primaryText(for: colorScheme))

                    Spacer()

                    // Controls on right - SWAPPED: Filter first, then Search
                    HStack(spacing: 12) {
                        // Filter button (now on left)
                        Button {
                            showingFilter = true
                        } label: {
                            Image(systemName: Design.Icons.filter)
                                .font(.system(size: 17, weight: .medium))
                                .foregroundStyle(Design.Colors.primaryText(for: colorScheme).opacity(0.9))
                                .glassButton(size: 38, colorScheme: colorScheme)
                        }
                        .buttonStyle(.plain)

                        // Search button (now on right/far right)
                        Button {
                            showingSearch = true
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

                // Category chips
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
            .padding(.top, 8) // REDUCED: Closer to status bar/notch

            Spacer()
        }
    }

    // MARK: - Actions

    private func shareArticle(_ article: Article) {
        // In real implementation, would present share sheet
        print("Share: \(article.title)")
    }
}

// MARK: - Preview

#Preview {
    TodayView()
}
