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
