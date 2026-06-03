//
//  LumitextRendering.swift
//  LumitextCore
//
//  The ONE renderer shared by the saver (full-screen) and the host app's live
//  preview. Because both instantiate the exact same SwiftUI view from the exact
//  same config, the preview is guaranteed WYSIWYG.
//
//  Resolution independence: font size & line spacing are expressed against a
//  reference screen height (LumitextConfig.referenceHeight = 1080) and scaled by
//  (actualHeight / referenceHeight). So one config renders proportionally the same
//  on a laptop, a 6K display, and the tiny System Settings thumbnail.
//

import SwiftUI

#if canImport(AppKit)
import AppKit
#endif

// MARK: - Color bridging

public extension RGBAColor {
    var swiftUIColor: Color {
        Color(.sRGB, red: red, green: green, blue: blue, opacity: alpha)
    }

    #if canImport(AppKit)
    var nsColor: NSColor {
        NSColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
    }

    init(_ nsColor: NSColor) {
        let c = nsColor.usingColorSpace(.sRGB) ?? nsColor
        self.init(red: Double(c.redComponent),
                  green: Double(c.greenComponent),
                  blue: Double(c.blueComponent),
                  alpha: Double(c.alphaComponent))
    }
    #endif
}

// MARK: - Font / weight bridging

public extension FontWeight {
    var swiftUIWeight: Font.Weight {
        switch self {
        case .thin: return .thin
        case .light: return .light
        case .regular: return .regular
        case .medium: return .medium
        case .semibold: return .semibold
        case .bold: return .bold
        case .heavy: return .heavy
        case .black: return .black
        }
    }
}

// MARK: - SwiftUI alignment bridging

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
            let scale = max(geo.size.height, 1) / LumitextConfig.referenceHeight
            let size = config.fontSize * scale
            let spacing = config.lineSpacing * scale
            let alignment = Alignment(
                horizontal: config.horizontalAlignment.swiftUI,
                vertical: config.verticalAlignment.swiftUI
            )

            ZStack(alignment: alignment) {
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
        }
        .ignoresSafeArea()
    }

    /// System font when family is empty, otherwise the named family (weight applied
    /// where supported). If a custom family is unavailable in the current process's
    /// sandbox, SwiftUI falls back to the system font automatically.
    private func resolvedFont(pointSize: CGFloat) -> Font {
        if config.fontFamily.isEmpty {
            return .system(size: pointSize, weight: config.fontWeight.swiftUIWeight)
        }
        return .custom(config.fontFamily, size: pointSize)
            .weight(config.fontWeight.swiftUIWeight)
    }
}
