//
//  MultilineTextField.swift
//  Lumitext
//
//  A multi-line plain-text editor backed directly by NSTextView. SwiftUI's
//  TextEditor cancels in-flight IME composition (the marked pinyin/kana the user
//  is still typing) because the bound value churns mid-composition and the round
//  trip resets the marked text. This wrapper reads the text back ONLY once the IME
//  has committed — while `hasMarkedText()` is true it neither propagates the value
//  out nor overwrites the view — so Chinese/Japanese/Korean input composes normally.
//
//  The placeholder is drawn by the text view itself so it can account for marked
//  text: it disappears the instant composition starts, not only once text commits.
//

import SwiftUI
import AppKit

struct MultilineTextField: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String = ""

    func makeNSView(context: Context) -> NSScrollView {
        let textView = PlaceholderTextView(frame: .zero)
        textView.placeholderString = placeholder
        textView.delegate = context.coordinator
        textView.string = text
        textView.font = .preferredFont(forTextStyle: .body)
        textView.isRichText = false
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 0, height: 4)
        textView.isVerticallyResizable = true
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)

        let scrollView = NSScrollView()
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? PlaceholderTextView else { return }
        // Keep the coordinator's binding current so committed text always writes
        // back through the latest closure, not the one captured at creation.
        context.coordinator.text = $text
        textView.placeholderString = placeholder
        // Never overwrite while the IME is composing — it would cancel the marked
        // text. Only push a genuine external change (preset, programmatic load).
        if !textView.hasMarkedText(), textView.string != text {
            textView.string = text
            textView.needsDisplay = true   // refresh the placeholder visibility
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>
        init(text: Binding<String>) { self.text = text }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            // Wait for the IME to commit before propagating — reading marked text
            // back out is exactly what cancels composition.
            guard !textView.hasMarkedText() else { return }
            text.wrappedValue = textView.string
        }
    }
}

/// NSTextView that draws a placeholder while it is genuinely empty — no committed
/// string AND no in-flight IME composition — so the hint clears the moment the
/// user starts typing (including the first marked pinyin character).
private final class PlaceholderTextView: NSTextView {
    var placeholderString = "" { didSet { needsDisplay = true } }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard string.isEmpty, !hasMarkedText(), !placeholderString.isEmpty else { return }
        let attrs: [NSAttributedString.Key: Any] = [
            .foregroundColor: NSColor.placeholderTextColor,
            .font: font ?? .preferredFont(forTextStyle: .body),
        ]
        let origin = NSPoint(
            x: textContainerInset.width + (textContainer?.lineFragmentPadding ?? 0),
            y: textContainerInset.height
        )
        (placeholderString as NSString).draw(at: origin, withAttributes: attrs)
    }

    // Redraw on every text/composition change so the placeholder appears/disappears
    // in step with marked text, not just committed text.
    override func didChangeText() {
        super.didChangeText()
        needsDisplay = true
    }

    override func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        super.setMarkedText(string, selectedRange: selectedRange, replacementRange: replacementRange)
        needsDisplay = true
    }

    override func unmarkText() {
        super.unmarkText()
        needsDisplay = true
    }
}
