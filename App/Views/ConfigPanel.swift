//
//  ConfigPanel.swift
//  Lumitext
//
//  The editing controls, organized as section cards on the night-indigo design
//  language: text → font → colors (presets + pickers) → position. Bound directly
//  to the model's LumitextConfig; AppModel's debounced autosave persists changes.
//  Labeled rows share one trailing-aligned label column (Theme.labelColumn) so
//  controls line up across cards.
//

import SwiftUI
import LumitextCore

struct ConfigPanel: View {
    @Binding var config: LumitextConfig
    let fontFamilies: [String]

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Below this WCAG ratio the text is essentially indistinguishable from the
    /// background on a real screen; warn before the user walks away.
    private static let contrastWarnThreshold = 1.6

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.s3) {
                SectionCard(titleKey: "Text", symbol: "character.cursor.ibeam") {
                    textEditor
                }

                SectionCard(titleKey: "Font", symbol: "textformat") {
                    VStack(spacing: Theme.s3) {
                        row("Family") {
                            FontPickerField(family: $config.fontFamily, families: fontFamilies)
                                .frame(maxWidth: 190)
                        }

                        row("Weight") {
                            Picker("", selection: $config.fontWeight) {
                                ForEach(FontWeight.allCases, id: \.self) { w in
                                    Text(LocalizedStringKey(w.rawValue.capitalized)).tag(w)
                                }
                            }
                            .labelsHidden()
                            .accessibilityLabel(Text("Weight"))
                            .frame(maxWidth: 190)
                        }

                        row("Size") {
                            HStack(spacing: Theme.s2) {
                                Slider(value: $config.fontSize, in: 24...480, step: 1)
                                    .accessibilityLabel(Text("Size"))
                                sizeField
                                Text(verbatim: "pt")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                }

                colorsCard

                SectionCard(titleKey: "Position", symbol: "squareshape.split.3x3") {
                    PositionGrid(
                        horizontal: $config.horizontalAlignment,
                        vertical: $config.verticalAlignment
                    )
                }
            }
            .padding(Theme.s4)
        }
        .scrollIndicators(.automatic)
    }

    /// Presets + pickers + a legibility guard, grouped as one color story.
    private var colorsCard: some View {
        // Compute once per render: the panel re-evaluates on every color-wheel
        // tick, and contrastRatio costs six pow() per call.
        let lowContrast = contrastRatio(text: config.textColor, background: config.backgroundColor) < Self.contrastWarnThreshold

        return SectionCard(titleKey: "Colors", symbol: "paintpalette") {
            VStack(alignment: .leading, spacing: Theme.s3) {
                ThemePresets(config: $config)

                Divider().overlay(Theme.hairline)

                row("Text") {
                    ColorPicker("", selection: $config.textColor.asColor, supportsOpacity: true)
                        .labelsHidden()
                        .accessibilityLabel(Text("Text"))
                        .help("Text color")
                }
                row("Background") {
                    ColorPicker("", selection: $config.backgroundColor.asColor, supportsOpacity: false)
                        .labelsHidden()
                        .accessibilityLabel(Text("Background"))
                        .help("Background color")
                }

                if lowContrast {
                    Label("Text may be hard to read on this background", systemImage: "eye.slash")
                        .font(.caption)
                        .foregroundStyle(Theme.warning)
                        .fixedSize(horizontal: false, vertical: true)
                        .transition(.opacity)
                }
            }
            .animation(reduceMotion ? nil : Theme.selectAnim, value: lowContrast)
        }
    }

    /// Multiline text input with a placeholder when empty (TextEditor has none).
    /// Deliberately keyed on `isEmpty` (not trimmed): while the user is typing
    /// whitespace the editor owns the canvas; the trimmed "blank" judgement
    /// lives in PreviewPane, where it reflects what the saver would show.
    private var textEditor: some View {
        ZStack(alignment: .topLeading) {
            TextEditor(text: $config.text)
                .font(.body)
                .frame(minHeight: 56, maxHeight: 96)
                .scrollContentBackground(.hidden)
                .padding(Theme.s2)

            if config.text.isEmpty {
                Text("Type something to display")
                    .font(.body)
                    .foregroundStyle(.tertiary)
                    // Align with the TextEditor's caret (its NSTextView adds a
                    // ~5pt horizontal container inset on top of our s2 padding).
                    .padding(.top, Theme.s2)
                    .padding(.leading, Theme.s2 + 5)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: Theme.rSmall, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.rSmall, style: .continuous)
                .strokeBorder(Theme.hairline, lineWidth: 1)
        )
    }

    /// Editable numeric size — the slider for coarse feel, this field for the
    /// exact value (standard macOS slider+field pairing). Clamps on commit.
    private var sizeField: some View {
        TextField("", value: Binding(
            get: { Int(config.fontSize) },
            set: { config.fontSize = Double(min(480, max(24, $0))) }
        ), format: .number)
            .textFieldStyle(.plain)
            .font(.system(size: 12, weight: .medium).monospacedDigit())
            .multilineTextAlignment(.trailing)
            .frame(width: 36)
            .padding(.vertical, 3)
            .padding(.horizontal, 5)
            .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: Theme.rSmall - 2, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.rSmall - 2, style: .continuous)
                    .strokeBorder(Theme.hairline, lineWidth: 1)
            )
            .accessibilityLabel(Text("Size"))
    }

    /// One labeled form row: trailing-aligned label in a fixed shared column,
    /// control in a consistent leading gutter.
    private func row<Content: View>(
        _ labelKey: LocalizedStringKey,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(alignment: .center, spacing: Theme.s3) {
            Text(labelKey)
                .frame(width: Theme.labelColumn, alignment: .trailing)
                // Controls carry their own accessibilityLabel; hiding the visual
                // label avoids VoiceOver announcing every row twice.
                .accessibilityHidden(true)
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
