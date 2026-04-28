//
//  LiquidGlassFilterSheet.swift
//  OpenRSS
//
//  A "Liquid Glass" bottom sheet for toggling article filters.
//
//  Design principles (matching LiquidGlassSearchBar):
//  • Frosted-glass material background via presentationBackground
//  • Icon chips with per-filter accent colors
//  • Active rows show a filled checkmark and a tinted row background
//  • "Clear All" fades in/out based on whether any filter is active
//  • Spring-animated toggle transitions
//

import SwiftUI

// MARK: - LiquidGlassFilterSheet

/// Bottom sheet that lets the user toggle `FilterOption`s on/off.
///
/// Present this with `.sheet(isPresented:)` and pass a binding to
/// `TodayViewModel.activeFilters`.
///
/// ```swift
/// .sheet(isPresented: $showingFilter) {
///     LiquidGlassFilterSheet(activeFilters: $viewModel.activeFilters)
/// }
/// ```
struct LiquidGlassFilterSheet: View {

    // MARK: - Bindings

    /// The set of currently active filters — mutated directly by toggle taps.
    @Binding var activeFilters: Set<FilterOption>

    // MARK: - Environment

    @Environment(\.dismiss)     private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            sheetHeader
            filterRows
        }
        .padding(.bottom, 24)
        // Glass material fills the entire sheet surface — matches headerView in TodayView
        .presentationBackground(colorScheme == .dark ? .regularMaterial : .thinMaterial)
        .presentationCornerRadius(Design.Radius.glass)
        .presentationDetents([.height(330)])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Header

    private var sheetHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Title row — checkmark sits on the same line as the title
            HStack(alignment: .center) {
                Text("Filter Articles")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(Design.Colors.primaryText(for: colorScheme))

                Spacer()

                // Blue checkmark dismiss button
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 34, height: 34)
                        .background(
                            Circle()
                                .fill(Design.Colors.primary)
                                .shadow(color: Design.Colors.primary.opacity(0.35), radius: 8, y: 3)
                        )
                }
                .buttonStyle(.plain)
            }

            // Subtitle row — "X active" + Clear All
            HStack(spacing: 8) {
                Text("\(activeFilters.count) active")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(Design.Colors.secondaryText(for: colorScheme))
                    .opacity(activeFilters.isEmpty ? 0 : 1)
                    .animation(Design.Animation.quick, value: activeFilters.isEmpty)

                if !activeFilters.isEmpty {
                    Button {
                        withAnimation(Design.Animation.standard) {
                            activeFilters.removeAll()
                        }
                    } label: {
                        Text("Clear All")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Design.Colors.primary)
                    }
                    .buttonStyle(.plain)
                    .transition(.scale(scale: 0.8).combined(with: .opacity))
                }
            }
            .animation(Design.Animation.standard, value: activeFilters.isEmpty)
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 14)
    }

    // MARK: - Filter Rows

    private var filterRows: some View {
        VStack(spacing: 10) {
            ForEach(FilterOption.allCases) { option in
                FilterOptionRow(
                    option:    option,
                    isActive:  activeFilters.contains(option),
                    colorScheme: colorScheme
                ) {
                    withAnimation(Design.Animation.standard) {
                        if activeFilters.contains(option) {
                            activeFilters.remove(option)
                        } else {
                            activeFilters.insert(option)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 16)
    }


}

// MARK: - FilterOptionRow

/// A single tappable row representing one filter option.
private struct FilterOptionRow: View {

    let option:      FilterOption
    let isActive:    Bool
    let colorScheme: ColorScheme
    let onTap:       () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 14) {
                // Colored icon chip
                iconChip

                // Label + description
                VStack(alignment: .leading, spacing: 2) {
                    Text(option.rawValue)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Design.Colors.primaryText(for: colorScheme))
                    Text(option.description)
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(Design.Colors.secondaryText(for: colorScheme))
                }

                Spacer()

                // Checkmark — morphs between outlined and filled
                Image(systemName: isActive ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(isActive ? Design.Colors.primary : Design.Colors.secondaryText(for: colorScheme).opacity(0.5))
                    .animation(Design.Animation.quick, value: isActive)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(rowBackground)
        }
        .buttonStyle(.plain)
    }

    // Colored square icon with rounded corners — matches Apple News-style filter rows
    private var iconChip: some View {
        Image(systemName: option.icon)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 36, height: 36)
            .background(
                RoundedRectangle(cornerRadius: 9)
                    .fill(Color(hex: option.iconColor))
                    .shadow(color: Color(hex: option.iconColor).opacity(0.35), radius: 6, y: 2)
            )
    }

    // Row card background — tints blue when active, glass otherwise
    private var rowBackground: some View {
        RoundedRectangle(cornerRadius: Design.Radius.standard)
            .fill(
                isActive
                    ? AnyShapeStyle(Design.Colors.primary.opacity(colorScheme == .dark ? 0.18 : 0.10))
                    : AnyShapeStyle(colorScheme == .dark ? .ultraThinMaterial : .regularMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Design.Radius.standard)
                    .strokeBorder(
                        isActive
                            ? Design.Colors.primary.opacity(0.35)
                            : Design.Colors.glassBorder(for: colorScheme),
                        lineWidth: isActive ? 1 : 0.5
                    )
            )
            .animation(Design.Animation.standard, value: isActive)
    }
}

// MARK: - Preview

#Preview("Light") {
    Color.white.ignoresSafeArea()
        .sheet(isPresented: .constant(true)) {
            LiquidGlassFilterSheet(activeFilters: .constant([.saved]))
        }
        .preferredColorScheme(.light)
}

#Preview("Dark") {
    Color(hex: "0a0e14").ignoresSafeArea()
        .sheet(isPresented: .constant(true)) {
            LiquidGlassFilterSheet(activeFilters: .constant([.unread, .today]))
        }
        .preferredColorScheme(.dark)
}
