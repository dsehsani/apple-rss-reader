//
//  CategoryChipView.swift
//  OpenRSS
//
//  Created by Darius Ehsani on 2/3/26.
//

import SwiftUI

/// Horizontal scrolling category chip for filtering articles
struct CategoryChipView: View {

    // MARK: - Properties

    let category: Category
    let isSelected: Bool
    let unreadCount: Int
    var onTap: (() -> Void)?

    // MARK: - Environment (Light/Dark Mode)

    @Environment(\.colorScheme) private var colorScheme

    // MARK: - Body

    var body: some View {
        Button {
            onTap?()
        } label: {
            HStack(spacing: 6) {
                Text(category.name)
                    .font(Design.Typography.chip)
                    .fontWeight(isSelected ? .semibold : .medium)
                    // Adaptive text color: white when selected, otherwise adaptive to color scheme
                    .foregroundStyle(
                        isSelected
                            ? .white
                            : Design.Colors.primaryText(for: colorScheme).opacity(0.9)
                    )

                // Unread badge (only show if > 0 and not selected)
                if unreadCount > 0 && !isSelected {
                    Text("\(unreadCount)")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Design.Colors.primary.opacity(0.8))
                        .clipShape(Capsule())
                }
            }
            .chipStyle(isSelected: isSelected, colorScheme: colorScheme)
        }
        .buttonStyle(.plain)
        .animation(Design.Animation.quick, value: isSelected)
    }
}

// MARK: - Category Chips Row

/// Horizontal scrolling row of category chips
struct CategoryChipsRow: View {

    let categories: [Category]
    let selectedCategory: Category?
    let unreadCountProvider: (Category) -> Int
    var onCategoryTap: ((Category) -> Void)?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Design.Spacing.small) {
                ForEach(categories) { category in
                    CategoryChipView(
                        category: category,
                        isSelected: selectedCategory?.id == category.id,
                        unreadCount: unreadCountProvider(category)
                    ) {
                        onCategoryTap?(category)
                    }
                }
            }
            .padding(.horizontal, Design.Spacing.edge)
            .padding(.vertical, Design.Spacing.small)
        }
    }
}

// MARK: - Preview

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()

        VStack(spacing: 20) {
            // Individual chips
            HStack {
                CategoryChipView(
                    category: Category.allUpdates,
                    isSelected: true,
                    unreadCount: 12
                )

                CategoryChipView(
                    category: Category(name: "Design", icon: "paintbrush.fill", color: .orange),
                    isSelected: false,
                    unreadCount: 5
                )

                CategoryChipView(
                    category: Category(name: "Tech News", icon: "cpu.fill", color: .blue),
                    isSelected: false,
                    unreadCount: 0
                )
            }

            // Full row
            CategoryChipsRow(
                categories: [
                    Category.allUpdates,
                    Category(name: "Design", icon: "paintbrush.fill", color: .orange),
                    Category(name: "Tech News", icon: "cpu.fill", color: .blue),
                    Category(name: "Work", icon: "briefcase.fill", color: .green),
                    Category(name: "Productivity", icon: "checkmark.circle.fill", color: .purple)
                ],
                selectedCategory: Category.allUpdates,
                unreadCountProvider: { _ in Int.random(in: 0...15) }
            )
        }
    }
}
