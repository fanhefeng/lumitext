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

    /// Slider comfort bounds extend to the current value (the model range is
    /// wider) and FREEZE while dragging — see the Size row comment.
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
    /// The text this view last wrote through the editor binding. Lets a
    /// config.text change that DIDN'T come from the editor (preset, programmatic
    /// load, undo) reset the notice — otherwise it latches "shortened" forever.
    @State private var lastEditorText: String?

    /// Derived contrast verdict. Recomputed only when a color changes (see
    /// `updateContrast`), NOT on every body evaluation — `contrastRatio` costs
    /// six `pow()` per call and body re-runs on every keystroke / slider tick.
    @State private var lowContrast = false
    private func updateContrast() {
        lowContrast = contrastRatio(text: config.textColor, background: config.backgroundColor) < Self.contrastWarnThreshold
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.s3) {
                SectionCard(titleKey: "Text", symbol: "character.cursor.ibeam") {
                    VStack(alignment: .leading, spacing: Theme.s2) {
                        textEditor
                        if showTruncationNotice {
                            // The model clamps silently (didSet); without this
                            // note a big paste just "loses" its tail. Short stable
                            // key + defaultValue (project convention) so a wording
                            // tweak can't silently drop the translation.
                            let notice = String(localized: "textTruncatedNotice",
                                                defaultValue: "The text was shortened to fit the screensaver's limits")
                            Label { Text(notice) } icon: { Image(systemName: "scissors") }
                                .font(.caption)
                                .foregroundStyle(Theme.warning)
                                .fixedSize(horizontal: false, vertical: true)
                                .transition(.opacity)
                                .onAppear {
                                    AccessibilityNotification.Announcement(notice).post()
                                }
                        }
                    }
                    .animation(reduceMotion ? nil : Theme.selectAnim, value: showTruncationNotice)
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

                        if FontCatalog.mayNotResolveInSaver(config.fontFamily) {
                            // The host preview can render fonts from anywhere;
                            // the sandboxed saver only reaches the system font
                            // folders — warn instead of letting WYSIWYG
                            // silently diverge (it falls back to the system
                            // font).
                            Label {
                                Text(String(localized: "fontMayNotResolveInSaver",
                                            defaultValue: "This font isn't in the system font folders — the screensaver may not see it and could fall back to the system font"))
                            } icon: {
                                Image(systemName: "exclamationmark.triangle")
                            }
                                .font(.caption)
                                .foregroundStyle(Theme.warning)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        row("Size") {
                            HStack(spacing: Theme.s2) {
                                clampedSlider(value: $config.fontSize,
                                              bounds: sizeBounds,
                                              frozenBounds: $sizeDragBounds,
                                              label: "Size")
                                sizeField
                                Text(verbatim: "pt")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .accessibilityHidden(true)
                            }
                        }

                        row("Spacing") {
                            HStack(spacing: Theme.s2) {
                                // lineSpacing is a first-class rendered/persisted model
                                // field — it needs a control, not just a JSON knob.
                                clampedSlider(value: $config.lineSpacing,
                                              bounds: spacingBounds,
                                              frozenBounds: $spacingDragBounds,
                                              label: "Line spacing")
                                Text(verbatim: "\(Int(config.lineSpacing.rounded()))")
                                    .font(.system(size: 12, weight: .medium).monospacedDigit())
                                    .foregroundStyle(.secondary)
                                    .frame(width: 36, alignment: .trailing)
                                    .accessibilityHidden(true)
                                Text(verbatim: "pt")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .accessibilityHidden(true)
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
        SectionCard(titleKey: "Colors", symbol: "paintpalette") {
            VStack(alignment: .leading, spacing: Theme.s3) {
                ThemePresets(config: $config)

                Divider().overlay(Theme.hairline)

                row("Text") {
                    ColorPicker("", selection: $config.textColor.asColor, supportsOpacity: true)
                        .labelsHidden()
                        // "Text" alone is ambiguous over VoiceOver (sounds like
                        // a text field); the full phrase names the control.
                        .accessibilityLabel(Text("Text color"))
                        .help("Text color")
                }
                row("Background") {
                    ColorPicker("", selection: $config.backgroundColor.asColor, supportsOpacity: false)
                        .labelsHidden()
                        .accessibilityLabel(Text("Background color"))
                        .help("Background color")
                }

                if lowContrast {
                    let warning = String(localized: "lowContrastWarning",
                                         defaultValue: "Text may be hard to read on this background")
                    Label { Text(warning) } icon: { Image(systemName: "eye.slash") }
                        .font(.caption)
                        .foregroundStyle(Theme.warning)
                        .fixedSize(horizontal: false, vertical: true)
                        .transition(.opacity)
                        // Transient warnings never enter the VoiceOver cursor on
                        // their own — announce the appearance.
                        .onAppear {
                            AccessibilityNotification.Announcement(warning).post()
                        }
                }
            }
            .animation(reduceMotion ? nil : Theme.selectAnim, value: lowContrast)
        }
        .onAppear { updateContrast() }
        .onChange(of: config.textColor) { _, _ in updateContrast() }
        .onChange(of: config.backgroundColor) { _, _ in updateContrast() }
    }

    /// Multiline text input with a placeholder when empty (TextEditor has none).
    /// Deliberately keyed on `isEmpty` (not trimmed): while the user is typing
    /// whitespace the editor owns the canvas; the trimmed "blank" judgement
    /// lives in PreviewPane, where it reflects what the saver would show.
    private var textEditor: some View {
        ZStack(alignment: .topLeading) {
            // Truncation-aware binding: the model's clamp reports whether it
            // shortened the input, so the notice is honest about THIS edit.
            TextEditor(text: Binding(
                get: { config.text },
                set: { newValue in
                    let result = LumitextConfig.clampTextReportingTruncation(newValue)
                    // Write the ALREADY-clamped value, not raw `newValue`. The old
                    // code stored the unclamped string and leaned on config.text's
                    // didSet to clamp it back a second time — so at the budget cap
                    // (2000 graphemes / 200 lines / 8000 scalars) the model briefly
                    // disagreed with what `get` returns, and SwiftUI force-rewrote
                    // the whole string into the NSTextView. That mid-edit full
                    // rewrite breaks IME composition (drops in-flight zh-Hans
                    // candidates) and snaps the caret to the end. Writing the clamped
                    // value here keeps model and binding read-back identical, so the
                    // binding is stable in both directions and there's nothing to
                    // force-rewrite.
                    config.text = result.text
                    showTruncationNotice = result.truncated
                    // Record the clamped value we wrote (use result.text, not a
                    // read-back of config.text) so there's no "when did didSet run"
                    // timing question — and so the .onChange(of: config.text) below
                    // compares clamped-against-clamped across frames, staying stable
                    // when it decides whether to clear the truncation notice.
                    lastEditorText = result.text
                }
            ))
                .font(.body)
                .frame(minHeight: 56, maxHeight: 96)
                .scrollContentBackground(.hidden)
                .padding(Theme.s2)
                .accessibilityLabel(Text("Screensaver text"))
                // A config.text change NOT made through this binding (preset,
                // programmatic load) means the notice — which describes the last
                // editor paste — no longer applies; clear it so it can't latch
                // "shortened" on top of unrelated, short text.
                .onChange(of: config.text) { _, newText in
                    if newText != lastEditorText {
                        showTruncationNotice = false
                        lastEditorText = newText
                    }
                }

            if config.text.isEmpty {
                Text("Type something to display")
                    .font(.body)
                    // .secondary, not .tertiary: this is the only instruction
                    // telling the user what the empty field is for, and
                    // tertiary-on-dark fails WCAG contrast.
                    .foregroundStyle(.secondary)
                    // Align with the TextEditor's caret (its NSTextView adds a
                    // ~5pt horizontal container inset on top of our s2 padding).
                    .padding(.top, Theme.s2)
                    .padding(.leading, Theme.s2 + 5)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .inputFieldChrome()
    }

    /// Editable numeric size — the slider for coarse feel, this field for the
    /// exact value (standard macOS slider+field pairing). Clamps on commit to the
    /// MODEL's range (1...2000), not the slider's comfort range (24...480): a
    /// hand-edited config outside the slider range must survive a field edit.
    private var sizeField: some View {
        TextField("", value: Binding(
            // rounded(), not truncation: a hand-edited fractional fontSize
            // (119.7) must display as the nearest point (120), matching what
            // is actually rendered/persisted as closely as an Int field can.
            get: { Int(config.fontSize.rounded()) },
            set: {
                config.fontSize = min(
                    LumitextConfig.fontSizeRange.upperBound,
                    max(LumitextConfig.fontSizeRange.lowerBound, Double($0))
                )
            }
        ), format: .number)
            .textFieldStyle(.plain)
            .font(.system(size: 12, weight: .medium).monospacedDigit())
            .multilineTextAlignment(.trailing)
            .frame(width: 36)
            .padding(.vertical, 3)
            .padding(.horizontal, 5)
            .inputFieldChrome(cornerRadius: Theme.rSmall - 2)
            // Distinct from the slider's "Size" so VoiceOver users can tell the
            // two controls in this row apart.
            .accessibilityLabel(Text("Size in points"))
    }

    /// A rounding slider whose comfort range extends to the current value and
    /// FREEZES while dragging — shared by Size and Spacing. Rationale:
    /// - Integer values via a rounding binding, NOT `step:` — on macOS a stepped
    ///   Slider renders one tick mark per step, and hundreds of ticks smear into
    ///   a white line under the track.
    /// - `bounds` already extends to the CURRENT value (see `sizeBounds`/
    ///   `spacingBounds`), so a hand-edited out-of-range value (the model legally
    ///   holds the full range) isn't collapsed the moment the thumb is touched.
    /// - Bounds FREEZE during the drag (`frozenBounds`), or the range would
    ///   shrink mid-drag and the thumb scale would jump under the cursor.
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
