//
//  ConfigPanel.swift
//  Lumitext
//
//  The editing controls, as a native grouped Form in the sidebar: text → font →
//  colors (presets + pickers) → position. Using Form + native controls lets macOS
//  own the row layout and label alignment (System Settings style). Bound directly
//  to the model's LumitextConfig; AppModel's debounced autosave persists changes.
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

    /// Slider comfort bounds extend to the current value (the model range is wider)
    /// and FREEZE while dragging — see `clampedSlider`.
    @State private var sizeDragBounds: ClosedRange<Double>?
    @State private var spacingDragBounds: ClosedRange<Double>?
    private var sizeBounds: ClosedRange<Double> {
        let c = LumitextConfig.fontSizeComfortRange
        return min(c.lowerBound, config.fontSize)...max(c.upperBound, config.fontSize)
    }
    private var spacingBounds: ClosedRange<Double> {
        let c = LumitextConfig.lineSpacingComfortRange
        return c.lowerBound...max(c.upperBound, config.lineSpacing)
    }

    /// True right after a paste/edit was shortened by the model's text budgets —
    /// silent truncation looks like data loss to the user.
    @State private var showTruncationNotice = false
    /// The text this view last wrote through the editor binding. Lets a config.text
    /// change that DIDN'T come from the editor (preset, programmatic load, undo)
    /// reset the notice — otherwise it latches "shortened" forever.
    @State private var lastEditorText: String?

    /// Derived contrast verdict. Recomputed only when a color changes (see
    /// `updateContrast`), NOT on every body evaluation — `contrastRatio` costs six
    /// `pow()` per call and body re-runs on every keystroke / slider tick.
    @State private var lowContrast = false
    private func updateContrast() {
        lowContrast = contrastRatio(text: config.textColor, background: config.backgroundColor) < Self.contrastWarnThreshold
    }

    var body: some View {
        Form {
            Section("Text") {
                // NSTextView-backed (see MultilineTextField) so IME composition
                // isn't dropped and the placeholder clears as soon as composing
                // starts; Return inserts a real newline.
                MultilineTextField(
                    text: editorBinding,
                    placeholder: String(localized: "Type something to display",
                                        defaultValue: "Type something to display")
                )
                .frame(minHeight: 60, maxHeight: 120)
                .accessibilityLabel(Text("Screensaver text"))
                // A config.text change NOT made through this binding (preset,
                // programmatic load) means the truncation notice — which describes
                // the last editor paste — no longer applies; clear it.
                .onChange(of: config.text) { _, newText in
                    if newText != lastEditorText {
                        showTruncationNotice = false
                        lastEditorText = newText
                    }
                }
                if showTruncationNotice {
                    let notice = String(localized: "textTruncatedNotice",
                                        defaultValue: "The text was shortened to fit the screensaver's limits")
                    warningRow(notice, symbol: "scissors")
                }
            }

            Section("Font") {
                Picker("Family", selection: $config.fontFamily) {
                    Text("System").tag("")
                    ForEach(fontFamilies.filter { !$0.isEmpty }, id: \.self) { family in
                        Text(family).tag(family)
                    }
                }
                Picker("Weight", selection: $config.fontWeight) {
                    ForEach(FontWeight.allCases, id: \.self) { w in
                        Text(LocalizedStringKey(w.rawValue.capitalized)).tag(w)
                    }
                }
                if FontCatalog.mayNotResolveInSaver(config.fontFamily) {
                    // The host preview can render fonts from anywhere; the sandboxed
                    // saver only reaches the system font folders — warn instead of
                    // letting WYSIWYG silently diverge (it falls back to the system font).
                    warningRow(String(localized: "fontMayNotResolveInSaver",
                                      defaultValue: "This font isn't in the system font folders — the screensaver may not see it and could fall back to the system font"),
                               symbol: "exclamationmark.triangle")
                }
                LabeledContent("Size") {
                    HStack(spacing: Theme.s2) {
                        clampedSlider(value: $config.fontSize, bounds: sizeBounds,
                                      frozenBounds: $sizeDragBounds, label: "Size")
                        sizeField
                        Text(verbatim: "pt").foregroundStyle(.secondary).accessibilityHidden(true)
                    }
                }
                LabeledContent("Spacing") {
                    HStack(spacing: Theme.s2) {
                        clampedSlider(value: $config.lineSpacing, bounds: spacingBounds,
                                      frozenBounds: $spacingDragBounds, label: "Line spacing")
                        Text(verbatim: "\(Int(config.lineSpacing.rounded())) pt")
                            .monospacedDigit().foregroundStyle(.secondary)
                            .frame(width: 44, alignment: .trailing).accessibilityHidden(true)
                    }
                }
            }

            Section("Colors") {
                ThemePresets(config: $config)
                ColorPicker("Text", selection: $config.textColor.asColor, supportsOpacity: true)
                ColorPicker("Background", selection: $config.backgroundColor.asColor, supportsOpacity: false)
                if lowContrast {
                    warningRow(String(localized: "lowContrastWarning",
                                      defaultValue: "Text may be hard to read on this background"),
                               symbol: "eye.slash")
                }
            }
            .onAppear { updateContrast() }
            .onChange(of: config.textColor) { _, _ in updateContrast() }
            .onChange(of: config.backgroundColor) { _, _ in updateContrast() }

            Section("Position") {
                Picker("Horizontal", selection: $config.horizontalAlignment) {
                    Text("Left").tag(LumitextCore.HorizontalAlignment.leading)
                    Text("Center").tag(LumitextCore.HorizontalAlignment.center)
                    Text("Right").tag(LumitextCore.HorizontalAlignment.trailing)
                }
                Picker("Vertical", selection: $config.verticalAlignment) {
                    Text("Top").tag(LumitextCore.VerticalAlignment.top)
                    Text("Middle").tag(LumitextCore.VerticalAlignment.center)
                    Text("Bottom").tag(LumitextCore.VerticalAlignment.bottom)
                }
            }
        }
        .formStyle(.grouped)
        .animation(reduceMotion ? nil : Theme.selectAnim, value: showTruncationNotice)
        .animation(reduceMotion ? nil : Theme.selectAnim, value: lowContrast)
    }

    /// Truncation-aware editor binding: the model's clamp reports whether it
    /// shortened the input, so the notice is honest about THIS edit. We write the
    /// ALREADY-clamped value (not the raw input): at the budget cap, relying on
    /// config.text's didSet to re-clamp makes the model momentarily disagree with
    /// `get`, so SwiftUI force-rewrites the whole field — which breaks IME
    /// composition (drops in-flight zh-Hans candidates) and snaps the caret to the
    /// end. Writing the clamped value keeps get/set read-back identical.
    private var editorBinding: Binding<String> {
        Binding(
            get: { config.text },
            set: { newValue in
                let result = LumitextConfig.clampTextReportingTruncation(newValue)
                config.text = result.text
                showTruncationNotice = result.truncated
                lastEditorText = result.text
            }
        )
    }

    /// Editable numeric size paired with the slider (standard macOS slider+field).
    /// Clamps on commit to the MODEL's range (1...2000), not the slider's comfort
    /// range — a hand-edited config outside the slider range must survive a field edit.
    private var sizeField: some View {
        TextField("", value: Binding(
            get: { Int(config.fontSize.rounded()) },
            set: {
                config.fontSize = min(
                    LumitextConfig.fontSizeRange.upperBound,
                    max(LumitextConfig.fontSizeRange.lowerBound, Double($0))
                )
            }
        ), format: .number)
            .multilineTextAlignment(.trailing)
            .monospacedDigit()
            .frame(width: 48)
            .accessibilityLabel(Text("Size in points"))
    }

    /// A rounding slider whose comfort range extends to the current value and
    /// FREEZES while dragging — shared by Size and Spacing.
    /// - Integer values via a rounding binding, NOT `step:` — a stepped macOS Slider
    ///   renders one tick per step, and hundreds of ticks smear into a white line.
    /// - `bounds` already extends to the CURRENT value, so a hand-edited
    ///   out-of-range value isn't collapsed the moment the thumb is touched.
    /// - Bounds FREEZE during the drag, or the range would shrink mid-drag and the
    ///   thumb would jump under the cursor.
    private func clampedSlider(
        value: Binding<Double>,
        bounds: ClosedRange<Double>,
        frozenBounds: Binding<ClosedRange<Double>?>,
        label: LocalizedStringKey
    ) -> some View {
        Slider(value: Binding(
            get: { value.wrappedValue },
            set: { value.wrappedValue = $0.rounded() }
        ), in: frozenBounds.wrappedValue ?? bounds) { editing in
            frozenBounds.wrappedValue = editing ? bounds : nil
        }
        .accessibilityLabel(Text(label))
        .accessibilityValue(Text("\(Int(value.wrappedValue.rounded())) points"))
    }

    /// A caption-styled inline warning row (truncation / font / contrast), with a
    /// VoiceOver announcement since transient warnings never enter the cursor on
    /// their own.
    private func warningRow(_ message: String, symbol: String) -> some View {
        Label { Text(message) } icon: { Image(systemName: symbol) }
            .font(.caption)
            .foregroundStyle(Theme.warning)
            .fixedSize(horizontal: false, vertical: true)
            .transition(.opacity)
            .onAppear { AccessibilityNotification.Announcement(message).post() }
    }
}
