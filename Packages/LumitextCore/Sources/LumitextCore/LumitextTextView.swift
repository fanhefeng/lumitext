//
//  LumitextTextView.swift
//  LumitextCore
//
//  The ONE renderer shared by the saver (full-screen) and the host app's live
//  preview. Both instantiate this exact view from the exact same config, so the
//  preview is guaranteed WYSIWYG.
//
//  Resolution independence: font size & line spacing are expressed against a
//  reference screen height (LumitextConfig.referenceHeight = 1080) and scaled by
//  (actualHeight / referenceHeight), so one config renders proportionally the same
//  on a laptop, a 6K display, and the tiny System Settings thumbnail.
//

import SwiftUI

#if canImport(AppKit)
import AppKit
#endif

// MARK: - Alignment bridging

public extension LumitextCore.HorizontalAlignment {
    var swiftUI: SwiftUI.HorizontalAlignment {
        switch self {
        case .leading: return .leading
        case .center: return .center
        case .trailing: return .trailing
        }
    }
    var textAlignment: TextAlignment {
        switch self {
        case .leading: return .leading
        case .center: return .center
        case .trailing: return .trailing
        }
    }
}

public extension LumitextCore.VerticalAlignment {
    var swiftUI: SwiftUI.VerticalAlignment {
        switch self {
        case .top: return .top
        case .center: return .center
        case .bottom: return .bottom
        }
    }
}

// MARK: - The shared renderer

/// Renders a LumitextConfig. Fills its container; positions the text block per the
/// config's alignment; scales typography relative to the container height so the
/// same config is a faithful miniature in a small preview.
public struct LumitextTextView: View {
    public let config: LumitextConfig

    public init(config: LumitextConfig) {
        self.config = config
    }

    public var body: some View {
        GeometryReader { geo in
            // Scale is HEIGHT-only by design: width participates in wrapping (text
            // wraps at the container's right edge), not in type size, so a narrow
            // container wraps more instead of shrinking the glyphs — matching how
            // the same config behaves across screen aspects. Degenerate widths
            // during transient layout passes are safe: the wrap width floors at 0
            // and .clipped() bounds the cost.
            let scale = max(geo.size.height, 1) / LumitextConfig.referenceHeight
            let size = config.fontSize * scale
            let spacing = config.lineSpacing * scale
            let alignment = Alignment(
                horizontal: config.horizontalAlignment.swiftUI,
                vertical: config.verticalAlignment.swiftUI
            )

            // Positioning is handled by the Text's own full-size frame(alignment:)
            // below, so the ZStack needs no alignment of its own.
            ZStack {
                config.backgroundColor.swiftUIColor

                Text(config.text)
                    .font(resolvedFont(pointSize: size))
                    .foregroundStyle(config.textColor.swiftUIColor)
                    .multilineTextAlignment(config.horizontalAlignment.textAlignment)
                    .lineSpacing(spacing)
                    .padding(size * 0.25)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
            }
            .frame(width: geo.size.width, height: geo.size.height)
            // Oversized text must never spill past the container; clipping here
            // means no consumer (saver, preview, snapshot) can forget to.
            .clipped()
        }
        .ignoresSafeArea()
    }

    /// System font when family is empty. For a named family, resolve the actual
    /// weighted face via NSFontDescriptor (`Font.custom(...).weight(...)` ignores
    /// the weight for many families). If the family is unavailable in the current
    /// process's sandbox, fall back to `.custom`, which itself falls back to the
    /// system font.
    private func resolvedFont(pointSize: CGFloat) -> Font {
        if config.fontFamily.isEmpty {
            return .system(size: pointSize, weight: config.fontWeight.swiftUIWeight)
        }
        #if canImport(AppKit)
        if let nsFont = NSFont.lumitextFont(
            family: config.fontFamily,
            weight: config.fontWeight.nsWeight,
            size: pointSize
        ) {
            return Font(nsFont)
        }
        #endif
        return .custom(config.fontFamily, size: pointSize)
            .weight(config.fontWeight.swiftUIWeight)
    }
}
