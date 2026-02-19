//
//  LiquidGlassSearchBar.swift
//  OpenRSS
//
//  A reusable "Liquid Glass" search bar component.
//
//  Design principles:
//  • Frosted-glass surface  — material blur + gradient shimmer border
//  • Fluid motion          — organic spring transitions on appear/dismiss
//  • Active icon glow      — search icon gains a blue pulse when focused
//  • Adaptive             — responds to light/dark mode seamlessly
//

import SwiftUI

// MARK: - LiquidGlassSearchBar

/// A polished, glassmorphic search bar.
///
/// Bind `text` to `SearchViewModel.searchText` and `isActive` to the
/// parent view's `showingSearch` toggle.  The bar manages its own focus
/// state and cancel/clear actions internally.
///
/// ```swift
/// LiquidGlassSearchBar(
///     text:     $viewModel.searchViewModel.searchText,
///     isActive: $showingSearch
/// )
/// ```
struct LiquidGlassSearchBar: View {

    // MARK: - Bindings

    /// The live search query string — bind to SearchViewModel.searchText.
    @Binding var text: String

    /// Controls whether the search bar is visible. Set to `false` to dismiss.
    @Binding var isActive: Bool

    // MARK: - Private State

    /// Tracks keyboard focus to drive the icon-glow animation.
    @FocusState private var isFocused: Bool

    /// Scales the icon slightly on focus for a subtle "pulse" feel.
    @State private var iconScale: CGFloat = 1.0

    // MARK: - Environment

    @Environment(\.colorScheme) private var colorScheme

    // MARK: - Body

    var body: some View {
        HStack(spacing: 10) {
            searchIcon
            searchField
            if !text.isEmpty { clearButton }
            cancelButton
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(glassBackground)
        // Appear: grow from trailing edge (where the search button lives)
        .transition(
            .asymmetric(
                insertion: .scale(scale: 0.88, anchor: .trailing)
                    .combined(with: .opacity),
                removal:   .scale(scale: 0.88, anchor: .trailing)
                    .combined(with: .opacity)
            )
        )
        // Auto-focus the text field when the bar becomes active
        .onChange(of: isActive) { _, newValue in
            if newValue {
                // Small delay so the animation completes before the keyboard rises
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    isFocused = true
                }
            }
        }
        // Drive icon scale from focus state
        .onChange(of: isFocused) { _, focused in
            withAnimation(Design.Animation.quick) {
                iconScale = focused ? 1.15 : 1.0
            }
        }
    }

    // MARK: - Sub-views

    /// Magnifying glass icon that glows blue when the field is focused.
    private var searchIcon: some View {
        Image(systemName: "magnifyingglass")
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(
                isFocused
                    ? Design.Colors.primary
                    : Design.Colors.secondaryText(for: colorScheme)
            )
            // Blue glow ring — only visible while focused
            .shadow(
                color: isFocused ? Design.Colors.primary.opacity(0.65) : .clear,
                radius: 7
            )
            .scaleEffect(iconScale)
            .animation(Design.Animation.quick, value: isFocused)
    }

    /// The plain text field — no internal chrome so we own the whole pill.
    private var searchField: some View {
        TextField("Search articles…", text: $text)
            .font(.system(size: 15, weight: .regular))
            .foregroundStyle(Design.Colors.primaryText(for: colorScheme))
            .tint(Design.Colors.primary)          // cursor color
            .focused($isFocused)
            .submitLabel(.search)
            .autocorrectionDisabled()
    }

    /// Appears as soon as text is entered; clears text without dismissing bar.
    private var clearButton: some View {
        Button {
            withAnimation(Design.Animation.quick) { text = "" }
        } label: {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 16))
                .foregroundStyle(Design.Colors.secondaryText(for: colorScheme))
        }
        .buttonStyle(.plain)
        .transition(.scale(scale: 0.5).combined(with: .opacity))
    }

    /// Always visible; dismisses the search bar and clears text on tap.
    private var cancelButton: some View {
        Button {
            withAnimation(Design.Animation.standard) {
                text = ""
                isActive = false
            }
            isFocused = false
        } label: {
            Text("Cancel")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Design.Colors.primary)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Glass Background

    /// Frosted-glass capsule with a shimmering gradient border.
    private var glassBackground: some View {
        Capsule()
            .fill(colorScheme == .dark ? AnyShapeStyle(.ultraThinMaterial)
                                       : AnyShapeStyle(.regularMaterial))
            .overlay(shimmerBorder)
            // Lift shadow — slightly stronger while focused
            .shadow(
                color: colorScheme == .dark
                    ? .black.opacity(isFocused ? 0.45 : 0.3)
                    : .black.opacity(isFocused ? 0.18 : 0.1),
                radius: isFocused ? 18 : 12,
                y: 4
            )
            .animation(Design.Animation.standard, value: isFocused)
    }

    /// Diagonal gradient stroke that catches the "light" from the top-left,
    /// creating the shimmering liquid glass highlight.
    private var shimmerBorder: some View {
        Capsule()
            .strokeBorder(
                LinearGradient(
                    colors: colorScheme == .dark
                        ? [
                            Color.white.opacity(0.35),
                            Color.white.opacity(0.12),
                            Color.white.opacity(0.04)
                          ]
                        : [
                            Color.white.opacity(0.95),
                            Color.white.opacity(0.55),
                            Color.black.opacity(0.04)
                          ],
                    startPoint: .topLeading,
                    endPoint:   .bottomTrailing
                ),
                lineWidth: 0.75
            )
    }
}

// MARK: - Preview

#Preview("Light mode") {
    ZStack {
        Color(hex: "f0f0f5").ignoresSafeArea()
        VStack(spacing: 20) {
            // Active with text
            StatefulPreviewWrapper(text: "Swift", active: true) { text, active in
                LiquidGlassSearchBar(text: text, isActive: active)
            }
            // Active, empty
            StatefulPreviewWrapper(text: "", active: true) { text, active in
                LiquidGlassSearchBar(text: text, isActive: active)
            }
        }
        .padding()
    }
    .preferredColorScheme(.light)
}

#Preview("Dark mode") {
    ZStack {
        Color(hex: "0a0e14").ignoresSafeArea()
        VStack(spacing: 20) {
            StatefulPreviewWrapper(text: "RSS feeds", active: true) { text, active in
                LiquidGlassSearchBar(text: text, isActive: active)
            }
            StatefulPreviewWrapper(text: "", active: true) { text, active in
                LiquidGlassSearchBar(text: text, isActive: active)
            }
        }
        .padding()
    }
    .preferredColorScheme(.dark)
}

// MARK: - Preview Helper

/// Minimal wrapper that gives @Binding state to #Preview closures.
private struct StatefulPreviewWrapper<Content: View>: View {
    @State var text: String
    @State var active: Bool
    let content: (Binding<String>, Binding<Bool>) -> Content

    var body: some View {
        content($text, $active)
    }
}
