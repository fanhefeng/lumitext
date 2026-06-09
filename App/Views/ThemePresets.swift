//
//  ThemePresets.swift
//  Lumitext
//
//  One-click style presets: each chip previews its own background/text colors
//  (an "Aa" swatch). Applying sets only the two colors, leaving the user's text,
//  font, size, and position untouched.
//

import SwiftUI
import LumitextCore

struct StylePreset: Identifiable {
    // Stable identity is the preset's name, NOT its colors: two presets that
    // happened to share a background+text pair would collide on a color-derived
    // id and break ForEach's view identity.
    let id: String
    let nameKey: LocalizedStringKey
    let background: RGBAColor
    let text: RGBAColor

    static let all: [StylePreset] = [
        .init(id: "midnight", nameKey: "Midnight", background: .defaultBackground, text: .white),
        .init(id: "ink", nameKey: "Ink", background: .black, text: .white),
        .init(id: "gold", nameKey: "Gold", background: RGBAColor(red: 0.07, green: 0.05, blue: 0.03),
              text: RGBAColor(red: 1.0, green: 0.84, blue: 0.40)),
        .init(id: "neon", nameKey: "Neon", background: RGBAColor(red: 0.05, green: 0.02, blue: 0.12),
              text: RGBAColor(red: 0.42, green: 0.96, blue: 0.93)),
        .init(id: "forest", nameKey: "Forest", background: RGBAColor(red: 0.04, green: 0.10, blue: 0.07),
              text: RGBAColor(red: 0.84, green: 0.95, blue: 0.87)),
        .init(id: "paper", nameKey: "Paper", background: RGBAColor(red: 0.96, green: 0.95, blue: 0.91),
              text: RGBAColor(red: 0.12, green: 0.11, blue: 0.10)),
    ]
}

struct ThemePresets: View {
    @Binding var config: LumitextConfig

    var body: some View {
        HStack(spacing: Theme.s2) {
            ForEach(StylePreset.all) { preset in
                chip(preset)
            }
        }
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private func chip(_ preset: StylePreset) -> some View {
        // Approximate, not exact: a preset color that round-trips through the
        // ColorPicker (RGBAColor → NSColor → RGBAColor) drifts below display
        // precision, and exact Double == would silently de-highlight the chip.
        let selected = config.backgroundColor.isApproximately(preset.background)
            && config.textColor.isApproximately(preset.text)
        return Button {
            withAnimation(reduceMotion ? nil : Theme.selectAnim) {
                config.backgroundColor = preset.background
                config.textColor = preset.text
            }
        } label: {
            VStack(spacing: 3) {
                Text("Aa")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(preset.text.swiftUIColor)
                    .frame(width: 40, height: 28)
                    .background(
                        preset.background.swiftUIColor,
                        in: RoundedRectangle(cornerRadius: Theme.rSmall, style: .continuous)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.rSmall, style: .continuous)
                            .strokeBorder(selected ? Theme.accent : Theme.hairline, lineWidth: selected ? 2 : 1)
                    )
                Text(preset.nameKey)
                    .font(.system(size: 9))
                    .foregroundStyle(selected ? Color.primary : Color.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
        .help(Text(preset.nameKey))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(preset.nameKey))
        .accessibilityHint(Text("Applies this color preset"))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
