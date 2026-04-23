//
//  DesignSystem.swift
//  OpenRSS
//
//  Created by Darius Ehsani on 2/3/26.
//

import Foundation
import SwiftUI

// MARK: - Design Tokens

/// Centralized design system for consistent styling across the app
enum Design {

    // MARK: - Colors

    enum Colors {
        /// Primary accent — Apple's refined CTA blue (#0071E3, used on apple.com buy buttons).
        /// Deeper and more deliberate than a flat system blue; reads as intentional, not default.
        static let primary = Color(hex: "0071E3")

        /// Card background (dark mode) — Apple's standard system card surface (#1C1C1E).
        /// Neutral charcoal, no blue tint. Depth comes from contrast against the near-black bg.
        static let cardBackground = Color(hex: "1C1C1E")

        /// Secondary text (dark mode) — pure neutral gray (#8E8E93, Apple system secondary).
        /// Replacing the old blue-tinted #9daab9 which made everything feel "developer default".
        static let secondaryText = Color(hex: "8E8E93")

        /// Subtle border — barely-there, used to separate cards in dark mode
        static let subtleBorder = Color.white.opacity(0.07)

        /// Glass border color
        static let glassBorder = Color.white.opacity(0.08)

        // MARK: - Adaptive Colors (Light/Dark Mode)

        /// Adaptive background - deep blue/black in dark, soft off-white in light
        static let adaptiveBackground = Color("AdaptiveBackground")

        /// Adaptive primary text - white in dark, dark gray in light
        static let adaptivePrimaryText = Color("AdaptivePrimaryText")

        /// Adaptive secondary text
        static let adaptiveSecondaryText = Color("AdaptiveSecondaryText")

        /// Adaptive card background
        static let adaptiveCardBackground = Color("AdaptiveCardBackground")

        /// Fallback adaptive colors using system colors
        /// Adaptive background color
        /// Page background.
        /// Dark: near-black #0C0C0E — refined, no blue tint, depth from card contrast not hue.
        /// Light: Apple systemGroupedBackground #F2F2F7 — cards pop as white against this.
        static func background(for colorScheme: ColorScheme) -> Color {
            colorScheme == .dark ? Color(hex: "0C0C0E") : Color(hex: "F2F2F7")
        }

        /// Primary text — near-black Apple ink in light; true white in dark.
        static func primaryText(for colorScheme: ColorScheme) -> Color {
            colorScheme == .dark ? .white : Color(hex: "1D1D1F")
        }

        /// Secondary text — pure neutral gray. No blue tint, no color bias.
        static func secondaryText(for colorScheme: ColorScheme) -> Color {
            colorScheme == .dark ? Color(hex: "8E8E93") : Color(hex: "6E6E73")
        }

        /// Card / list-row surface.
        /// Dark: #1C1C1E (Apple standard — warm charcoal, not blue-gray).
        /// Light: pure white against the F2F2F7 background.
        static func cardBackground(for colorScheme: ColorScheme) -> Color {
            colorScheme == .dark ? Color(hex: "1C1C1E") : Color.white
        }

        /// Hairline border. Barely visible — just enough to separate surfaces, not grid-like.
        static func glassBorder(for colorScheme: ColorScheme) -> Color {
            colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.05)
        }

        static func glassHighlight(for colorScheme: ColorScheme) -> Color {
            colorScheme == .dark ? Color.white.opacity(0.2) : Color.white.opacity(0.9)
        }

        /// Inactive tab text — muted, clearly subordinate to the active blue.
        static func tabBarInactiveText(for colorScheme: ColorScheme) -> Color {
            colorScheme == .dark ? Color(hex: "8E8E93") : Color(hex: "8E8E93")
        }

        /// Tinted accent surface — for icon backgrounds, selected states, subtle highlights.
        static func accentSubtle(for colorScheme: ColorScheme) -> Color {
            colorScheme == .dark ? primary.opacity(0.15) : primary.opacity(0.08)
        }
    }

    // MARK: - Spacing

    enum Spacing {
        /// Edge/horizontal padding (16pt)
        static let edge: CGFloat = 16

        /// Card internal padding (16pt)
        static let cardPadding: CGFloat = 16

        /// Gap between cards (16pt)
        static let cardGap: CGFloat = 16

        /// Section spacing (24pt)
        static let section: CGFloat = 24

        /// Small spacing (8pt)
        static let small: CGFloat = 8

        /// Extra small spacing (4pt)
        static let xSmall: CGFloat = 4
    }

    // MARK: - Corner Radius

    enum Radius {
        /// Standard corner radius (12pt)
        static let standard: CGFloat = 12

        /// Large corner radius (16pt)
        static let large: CGFloat = 16

        /// Small corner radius (8pt)
        static let small: CGFloat = 8

        /// Extra large for glass containers (24pt)
        static let glass: CGFloat = 24

        /// Tab bar radius (28pt)
        static let tabBar: CGFloat = 28

        /// Pill/chip radius
        static let pill: CGFloat = .infinity
    }

    // MARK: - Glass Styling

    enum Glass {
        /// Glass highlight border color (top edge)
        static let highlightBorder = Color.white.opacity(0.15)

        /// Glass shadow border color (bottom edge)
        static let shadowBorder = Color.black.opacity(0.12)

        /// Inner glow for glass containers
        static let innerGlow = Color.white.opacity(0.04)

        /// Floating shadow — light, not dramatic
        static let floatingShadow = ShadowStyle(
            color: .black.opacity(0.18),
            radius: 16,
            x: 0,
            y: 6
        )
    }

    // MARK: - Typography

    enum Typography {
        /// Large title (34pt bold, like "Today")
        static let largeTitle = Font.system(size: 34, weight: .bold)

        /// Card title (20pt bold)
        static let cardTitle = Font.system(size: 20, weight: .bold)

        /// Body text (14pt regular)
        static let body = Font.system(size: 14, weight: .regular)

        /// Caption text (12pt medium, uppercase for source labels)
        static let caption = Font.system(size: 12, weight: .medium)

        /// Chip text (14pt semibold)
        static let chip = Font.system(size: 14, weight: .semibold)

        /// Tab label (10pt)
        static let tabLabel = Font.system(size: 10, weight: .medium)
    }

    // MARK: - Animation

    enum Animation {
        /// Standard spring animation
        static let standard = SwiftUI.Animation.spring(response: 0.3, dampingFraction: 0.8)

        /// Quick animation for micro-interactions
        static let quick = SwiftUI.Animation.spring(response: 0.2, dampingFraction: 0.9)

        /// Liquid glass spring animation - organic, fluid motion for tab bar pill
        /// Uses interactiveSpring for responsive, natural feel as the pill slides between tabs
        static let liquidSpring = SwiftUI.Animation.interactiveSpring(response: 0.5, dampingFraction: 0.7, blendDuration: 0.25)

        /// Card press scale factor
        static let pressScale: CGFloat = 0.98
    }

    // MARK: - Shadows

    enum Shadows {
        /// Card shadow — subtle in light mode, invisible in dark (depth = color contrast, not shadow).
        /// Heavy drop shadows are the #1 signal of a cheap app.
        static let card = ShadowStyle(
            color: .black.opacity(0.07),
            radius: 10,
            x: 0,
            y: 2
        )

        /// Slightly more present shadow for floating elements (tab bar, modals)
        static let floating = ShadowStyle(
            color: .black.opacity(0.12),
            radius: 20,
            x: 0,
            y: 6
        )
    }

    // MARK: - Icons

    enum Icons {
        // Tab bar icons
        static let today = "newspaper.fill"
        static let discover = "sparkles"
        static let saved = "bookmark.fill"
        static let sources = "antenna.radiowaves.left.and.right"
        static let settings = "gearshape.fill"
        static let profile = "person.crop.circle.fill"

        // Action icons
        static let bookmark = "bookmark"
        static let bookmarkFilled = "bookmark.fill"
        static let share = "square.and.arrow.up"
        static let search = "magnifyingglass"
        static let filter = "line.3.horizontal.decrease"
        static let add = "plus"
        static let chevronRight = "chevron.right"
        static let chevronDown = "chevron.down"
    }
}

// MARK: - Shadow Style

struct ShadowStyle {
    let color: Color
    let radius: CGFloat
    let x: CGFloat
    let y: CGFloat
}

// MARK: - Color Extension for Hex

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

// MARK: - View Modifiers

extension View {
    /// Apply card styling with liquid glass aesthetic
    func cardStyle() -> some View {
        self
            .background(Design.Colors.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: Design.Radius.standard))
            .overlay(
                RoundedRectangle(cornerRadius: Design.Radius.standard)
                    .stroke(Design.Colors.subtleBorder, lineWidth: 0.5)
            )
            // No shadow in dark mode — depth comes from #1C1C1E on #0C0C0E contrast
            .shadow(
                color: Design.Shadows.card.color,
                radius: Design.Shadows.card.radius,
                x: Design.Shadows.card.x,
                y: Design.Shadows.card.y
            )
    }

    /// Apply card styling with adaptive colors for light/dark mode
    func cardStyle(for colorScheme: ColorScheme) -> some View {
        self
            .background(Design.Colors.cardBackground(for: colorScheme))
            .clipShape(RoundedRectangle(cornerRadius: Design.Radius.standard))
            .overlay(
                RoundedRectangle(cornerRadius: Design.Radius.standard)
                    .stroke(
                        Design.Colors.glassBorder(for: colorScheme),
                        lineWidth: 0.5
                    )
            )
            // Dark mode: no shadow. Light mode: barely-there lift.
            .shadow(
                color: colorScheme == .dark ? .clear : .black.opacity(0.06),
                radius: 10,
                x: 0,
                y: 2
            )
    }

    /// Apply chip styling for category chips - polished glass pill style
    func chipStyle(isSelected: Bool) -> some View {
        self
            .padding(.horizontal, 18)
            .frame(height: 34)
            .background {
                if isSelected {
                    Capsule()
                        .fill(Design.Colors.primary)
                        // Restrained glow — present but not garish
                        .shadow(color: Design.Colors.primary.opacity(0.25), radius: 6, y: 2)
                } else {
                    Capsule()
                        .fill(.ultraThinMaterial)
                        .overlay(
                            Capsule()
                                .stroke(Color.white.opacity(0.1), lineWidth: 0.5)
                        )
                }
            }
            .clipShape(Capsule())
    }

    /// Apply chip styling with adaptive colors for light/dark mode
    func chipStyle(isSelected: Bool, colorScheme: ColorScheme) -> some View {
        self
            .padding(.horizontal, 18)
            .frame(height: 34)
            .background {
                if isSelected {
                    Capsule()
                        .fill(Design.Colors.primary)
                        .shadow(color: Design.Colors.primary.opacity(0.2), radius: 6, y: 2)
                } else {
                    Capsule()
                        .fill(colorScheme == .dark ? .ultraThinMaterial : .regularMaterial)
                        .overlay(
                            Capsule()
                                .stroke(Design.Colors.glassBorder(for: colorScheme), lineWidth: 0.5)
                        )
                }
            }
            .clipShape(Capsule())
    }

    /// Apply floating glass container style (for headers, tab bars)
    func glassContainer(cornerRadius: CGFloat = Design.Radius.glass) -> some View {
        self
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .stroke(
                                LinearGradient(
                                    colors: [
                                        Design.Glass.highlightBorder,
                                        Color.clear,
                                        Design.Glass.shadowBorder
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                ),
                                lineWidth: 1
                            )
                    )
                    .shadow(
                        color: Design.Glass.floatingShadow.color,
                        radius: Design.Glass.floatingShadow.radius,
                        x: Design.Glass.floatingShadow.x,
                        y: Design.Glass.floatingShadow.y
                    )
            )
    }

    /// Circular glass button style
    func glassButton(size: CGFloat = 40) -> some View {
        self
            .frame(width: size, height: size)
            .background(
                Circle()
                    .fill(.ultraThinMaterial)
                    .overlay(
                        Circle()
                            .stroke(Design.Colors.glassBorder, lineWidth: 1)
                    )
            )
            .clipShape(Circle())
    }

    /// Circular glass button style with adaptive colors for light/dark mode
    func glassButton(size: CGFloat = 40, colorScheme: ColorScheme) -> some View {
        self
            .frame(width: size, height: size)
            .background(
                Circle()
                    .fill(colorScheme == .dark ? .ultraThinMaterial : .regularMaterial)
                    .overlay(
                        Circle()
                            .stroke(Design.Colors.glassBorder(for: colorScheme), lineWidth: 1)
                    )
            )
            .clipShape(Circle())
    }
}
