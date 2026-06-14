//
//  Theme.swift
//  Lumitext
//
//  Layout tokens (spacing, radii, motion) plus a couple of reusable bits
//  (the pressable button style and the warning card). Colors are system-semantic
//  (accent + status), so the whole UI adapts to light/dark and to the user's
//  accent color automatically.
//

import SwiftUI

enum Theme {
    /// System accent — picks up the user's chosen highlight color.
    static let accent = Color.accentColor

    /// Status colors, mapped to the system palette so they read correctly in
    /// both appearances.
    static let ok = Color.green
    static let warning = Color.orange
    static let error = Color.red

    /// Adaptive hairline for the few places that still need a 1px edge
    /// (selectable cell/chip borders).
    static let hairline = Color.primary.opacity(0.12)

    /// Spacing rhythm (pt).
    static let s1: CGFloat = 4
    static let s2: CGFloat = 8
    static let s3: CGFloat = 12
    static let s4: CGFloat = 16
    static let s5: CGFloat = 24

    /// Corner radii.
    static let rSmall: CGFloat = 7
    static let rScreen: CGFloat = 12

    /// Two-tier motion rhythm: `selectAnim` for selection/state changes,
    /// `hoverAnim` for micro hover/press feedback (faster on purpose — pointer
    /// feedback should feel immediate, state changes deliberate).
    static let selectAnim = Animation.easeOut(duration: 0.18)
    static let hoverAnim = Animation.easeOut(duration: 0.12)
}

/// Interaction states for the custom chip/cell/field buttons: hover brightens,
/// press compresses slightly. `.plain` strips both on macOS; this style restores
/// them with one shared motion language. (Keyboard focus visibility stays with
/// the system focus ring, drawn at the AppKit level for any focusable control.)
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

/// Shared warning chrome: a Liquid Glass platter tinted toward the warning color,
/// with a leading icon. Used by the move-to-Applications notice and the
/// persistence-failure banner.
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
        .glassEffect(
            .regular.tint(Theme.warning.opacity(0.22)),
            in: RoundedRectangle(cornerRadius: Theme.rSmall, style: .continuous)
        )
    }
}
