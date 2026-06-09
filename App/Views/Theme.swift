//
//  Theme.swift
//  Lumitext
//
//  Design tokens (dark-first "night indigo" language). Semantic tokens only —
//  views never hard-code raw colors, so the language stays consistent and is
//  adjustable in one place.
//

import SwiftUI

enum Theme {
    /// Interactive accent — night indigo (#6366F1).
    static let accent = Color(red: 0.39, green: 0.40, blue: 0.95)

    /// The unified window backdrop (deep night indigo) the whole UI sits on.
    static let windowBackground = Color(red: 0.055, green: 0.07, blue: 0.13)

    /// Card/group surface on the window background.
    static let surface = Color.white.opacity(0.05)
    /// Slightly raised surface (e.g. inputs on a card).
    static let surfaceRaised = Color.white.opacity(0.08)
    /// Hairline borders (dark-first; the app forces dark appearance). 0.14 keeps the
    /// hairline feel while clearing visibility thresholds for low-vision users.
    static let hairline = Color.white.opacity(0.14)

    /// Status colors.
    static let ok = Color(red: 0.30, green: 0.85, blue: 0.45)
    static let warning = Color.orange
    /// Hard error (failed activation) — distinct from `warning`'s recoverable orange.
    static let error = Color.red

    /// Spacing rhythm (pt).
    static let s1: CGFloat = 4
    static let s2: CGFloat = 8
    static let s3: CGFloat = 12
    static let s4: CGFloat = 16
    static let s5: CGFloat = 24

    /// Corner radii.
    static let rSmall: CGFloat = 7
    static let rCard: CGFloat = 12
    static let rScreen: CGFloat = 12

    /// Shared trailing-aligned label column for form rows, so labels and controls
    /// line up across the Font and Colors cards (HIG settings convention).
    /// 80pt fits the longest English label ("Background") without wrapping.
    static let labelColumn: CGFloat = 80

    /// Two-tier motion rhythm: `selectAnim` for selection/state changes,
    /// `hoverAnim` for micro hover/press feedback (faster on purpose — pointer
    /// feedback should feel immediate, state changes deliberate).
    static let selectAnim = Animation.easeOut(duration: 0.18)
    static let hoverAnim = Animation.easeOut(duration: 0.12)
}

/// Interaction states for the custom chip/cell/field buttons: hover brightens,
/// press compresses slightly. `.plain` strips both on macOS; this style restores
/// them with one shared motion language for every custom control. (Keyboard
/// focus visibility stays with the system focus ring — Full Keyboard Access
/// draws it at the AppKit level for any focusable control.)
struct PressableButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Pressable(configuration: configuration)
    }

    private struct Pressable: View {
        let configuration: Configuration
        @State private var hovering = false
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        var body: some View {
            configuration.label
                .brightness(hovering ? 0.07 : 0)
                .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
                .animation(reduceMotion ? nil : Theme.hoverAnim, value: hovering)
                .animation(reduceMotion ? nil : Theme.hoverAnim, value: configuration.isPressed)
                .onHover { hovering = $0 }
        }
    }
}

extension ButtonStyle where Self == PressableButtonStyle {
    static var pressable: PressableButtonStyle { .init() }
}

extension View {
    /// Shared input-field chrome: a raised surface fill plus a hairline border,
    /// used by the text editor, the size field, and the font-picker trigger so
    /// the "editable control" look is defined once. `cornerRadius` defaults to
    /// `Theme.rSmall`; smaller fields (e.g. the inline size field) pass less.
    func inputFieldChrome(cornerRadius: CGFloat = Theme.rSmall) -> some View {
        background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Theme.hairline, lineWidth: 1)
            )
    }
}

/// Shared warning-card chrome (orange tint, hairline, leading icon) used by the
/// move-to-Applications notice and the persistence-failure banner.
struct WarningCard<Content: View>: View {
    let symbol: String
    @ViewBuilder var content: Content

    var body: some View {
        HStack(spacing: Theme.s3) {
            Image(systemName: symbol)
                .foregroundStyle(Theme.warning)
            content
        }
        .padding(Theme.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.warning.opacity(0.10), in: RoundedRectangle(cornerRadius: Theme.rSmall, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.rSmall, style: .continuous)
                .strokeBorder(Theme.warning.opacity(0.3), lineWidth: 1)
        )
    }
}

/// Section container with an SF-Symbol header — the grouped "card" used across
/// the config panel.
struct SectionCard<Content: View>: View {
    let titleKey: LocalizedStringKey
    let symbol: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.s3) {
            Label {
                Text(titleKey)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
            } icon: {
                Image(systemName: symbol)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.accent)
            }
            .labelStyle(.titleAndIcon)

            content
        }
        .padding(Theme.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.rCard, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.rCard, style: .continuous)
                .strokeBorder(Theme.hairline, lineWidth: 1)
        )
    }
}
