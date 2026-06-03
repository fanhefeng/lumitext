//
//  ConfigPanel.swift
//  Lumitext
//
//  The editing controls: text, font family/weight/size, colors, and 9-grid
//  alignment. Bound directly to the model's LumitextConfig; the debounced
//  autosave in AppModel persists changes to the screensaver.
//

import SwiftUI
import LumitextCore

struct ConfigPanel: View {
    @Binding var config: LumitextConfig
    let fontFamilies: [String]

    var body: some View {
        Form {
            Section("Text") {
                TextEditor(text: $config.text)
                    .font(.body)
                    .frame(minHeight: 72)
                    .scrollContentBackground(.hidden)
                    .padding(6)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
            }

            Section("Font") {
                Picker("Family", selection: $config.fontFamily) {
                    ForEach(fontFamilies, id: \.self) { family in
                        Text(family.isEmpty ? "System" : family).tag(family)
                    }
                }

                Picker("Weight", selection: $config.fontWeight) {
                    ForEach(FontWeight.allCases, id: \.self) { w in
                        Text(w.rawValue.capitalized).tag(w)
                    }
                }

                LabeledContent("Size") {
                    HStack {
                        Slider(value: $config.fontSize, in: 24...480, step: 1)
                        Text("\(Int(config.fontSize))")
                            .monospacedDigit()
                            .frame(width: 44, alignment: .trailing)
                    }
                }
            }

            Section("Colors") {
                ColorPicker("Text", selection: $config.textColor.asColor, supportsOpacity: true)
                ColorPicker("Background", selection: $config.backgroundColor.asColor, supportsOpacity: false)
            }

            Section("Position") {
                Picker("Horizontal", selection: $config.horizontalAlignment) {
                    Text("Left").tag(HorizontalAlignment.leading)
                    Text("Center").tag(HorizontalAlignment.center)
                    Text("Right").tag(HorizontalAlignment.trailing)
                }
                .pickerStyle(.segmented)

                Picker("Vertical", selection: $config.verticalAlignment) {
                    Text("Top").tag(VerticalAlignment.top)
                    Text("Middle").tag(VerticalAlignment.center)
                    Text("Bottom").tag(VerticalAlignment.bottom)
                }
                .pickerStyle(.segmented)
            }
        }
        .formStyle(.grouped)
    }
}
