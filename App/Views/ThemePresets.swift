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
    let nameKey: LocalizedStringKey
    let background: RGBAColor
    let text: RGBAColor
    var id: String { "\(background.red),\(background.green),\(background.blue)-\(text.red),\(text.green),\(text.blue)" }

    static let all: [StylePreset] = [
        .init(nameKey: "Midnight", background: .defaultBackground, text: .white),
        .init(nameKey: "Ink", background: .black, text: .white),
        .init(nameKey: "Gold", background: RGBAColor(red: 0.07, green: 0.05, blue: 0.03),
              text: RGBAColor(red: 1.0, green: 0.84, blue: 0.40)),
        .init(nameKey: "Neon", background: RGBAColor(red: 0.05, green: 0.02, blue: 0.12),
              text: RGBAColor(red: 0.42, green: 0.96, blue: 0.93)),
        .init(nameKey: "Forest", background: RGBAColor(red: 0.04, green: 0.10, blue: 0.07),
              text: RGBAColor(red: 0.84, green: 0.95, blue: 0.87)),
        .init(nameKey: "Paper", background: RGBAColor(red: 0.96, green: 0.95, blue: 0.91),
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
