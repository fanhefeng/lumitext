//
//  ConfigPanel.swift
//  Lumitext
//
//  The editing controls, organized as section cards on the night-indigo design
//  language: text → presets → font → colors → position. Bound directly to the
//  model's LumitextConfig; AppModel's debounced autosave persists changes.
//

import SwiftUI
import LumitextCore

struct ConfigPanel: View {
    @Binding var config: LumitextConfig
    let fontFamilies: [String]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.s3) {
                SectionCard(titleKey: "Text", symbol: "character.cursor.ibeam") {
                    TextEditor(text: $config.text)
                        .font(.body)
                        .frame(minHeight: 56, maxHeight: 96)
                        .scrollContentBackground(.hidden)
                        .padding(Theme.s2)
                        .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: Theme.rSmall, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: Theme.rSmall, style: .continuous)
                                .strokeBorder(Theme.hairline, lineWidth: 1)
                        )
                }

                SectionCard(titleKey: "Presets", symbol: "sparkles") {
                    ThemePresets(config: $config)
                }

                SectionCard(titleKey: "Font", symbol: "textformat") {
                    VStack(spacing: Theme.s3) {
                        LabeledContent {
                            FontPickerField(family: $config.fontFamily, families: fontFamilies)
                                .frame(maxWidth: 190)
                        } label: {
                            Text("Family")
                        }

                        LabeledContent {
                            Picker("", selection: $config.fontWeight) {
                                ForEach(FontWeight.allCases, id: \.self) { w in
                                    Text(LocalizedStringKey(w.rawValue.capitalized)).tag(w)
                                }
                            }
                            .labelsHidden()
                            .accessibilityLabel(Text("Weight"))
                            .frame(maxWidth: 190)
                        } label: {
                            Text("Weight")
                        }

                        LabeledContent {
                            HStack(spacing: Theme.s2) {
                                Slider(value: $config.fontSize, in: 24...480, step: 1)
                                Text("\(Int(config.fontSize))")
                                    .font(.system(size: 12, weight: .medium).monospacedDigit())
                                    .foregroundStyle(.secondary)
                                    .frame(width: 34, alignment: .trailing)
                            }
                        } label: {
                            Text("Size")
                        }
                    }
                }

                SectionCard(titleKey: "Colors", symbol: "paintpalette") {
                    VStack(spacing: Theme.s3) {
                        LabeledContent {
                            ColorPicker("", selection: $config.textColor.asColor, supportsOpacity: true)
                                .labelsHidden()
                                .accessibilityLabel(Text("Text"))
                        } label: {
                            Text("Text")
                        }
                        LabeledContent {
                            ColorPicker("", selection: $config.backgroundColor.asColor, supportsOpacity: false)
                                .labelsHidden()
                                .accessibilityLabel(Text("Background"))
                        } label: {
                            Text("Background")
                        }
                    }
                }

                SectionCard(titleKey: "Position", symbol: "squareshape.split.3x3") {
                    HStack {
                        Spacer(minLength: 0)
                        PositionGrid(
                            horizontal: $config.horizontalAlignment,
                            vertical: $config.verticalAlignment
                        )
                        Spacer(minLength: 0)
                    }
                }
            }
            .padding(Theme.s4)
        }
        .scrollIndicators(.never)
    }
}
