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
        // usingColorSpace(_:) returns nil for pattern/catalog colors — falling
        // back to the ORIGINAL color would TRAP in redComponent before any
        // model clamp could run. Try a second RGB conversion, then a safe
        // opaque black: an exotic picker color must never crash the host.
        guard let c = nsColor.usingColorSpace(.sRGB) ?? nsColor.usingColorSpace(.genericRGB) else {
            self.init(red: 0, green: 0, blue: 0, alpha: 1)
            return
        }
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

    #if canImport(AppKit)
    var nsWeight: NSFont.Weight {
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
    #endif
}

/// Which font-file locations the sandboxed saver appex can actually read.
/// Pure path policy (no font APIs) so the host's "this font may not show in
/// the screensaver" warning is unit-testable in Core.
public enum FontPathPolicy {
    /// Locations every sandboxed process can read fonts from. ~/Library/Fonts,
    /// app bundles/containers, and network mounts are NOT on this list — fonts
    /// there render in the non-sandboxed host but silently fall back to the
    /// system font in the saver.
    public static let saverReadablePrefixes = ["/System/Library/", "/Library/Fonts/"]

    public static func mayNotResolveInSaver(fontAt path: String) -> Bool {
        !saverReadablePrefixes.contains { path.hasPrefix($0) }
    }
}

#if canImport(AppKit)
public extension NSFont {
    /// `availableFontFamilies` walks the font registry — far too expensive for
    /// the render path, which re-evaluates on every preview keystroke. Memoized
    /// per family name (font installs mid-session are rare; the host calls
    /// `lumitextInvalidateFamilyCache()` when it refreshes its family list).
    private static let lumitextCacheLock = NSLock()
    nonisolated(unsafe) private static var lumitextFamilyAvailable: [String: Bool] = [:]
    /// Resolved faces keyed by family|weight|size. The descriptor trait-MATCH in
    /// `lumitextFont` (not the availability check, which is already memoized) is
    /// the per-call cost, and `body` re-resolves on every layout pass / preview
    /// keystroke at a stable size — so cache the finished NSFont. Bounded: a live
    /// drag-resize sweeps many sizes, so clear past a cap rather than grow forever.
    nonisolated(unsafe) private static var lumitextFontCache: [String: NSFont] = [:]
    private static let lumitextFontCacheCap = 128

    /// Forget memoized availability AND resolved faces — call when the installed-
    /// font set may have changed (the host does, on every app re-activation), so a
    /// font installed (or replaced) mid-session starts rendering without a relaunch.
    static func lumitextInvalidateFamilyCache() {
        lumitextCacheLock.lock()
        lumitextFamilyAvailable.removeAll()
        lumitextFontCache.removeAll()
        lumitextCacheLock.unlock()
    }

    private static func lumitextFamilyIsAvailable(_ family: String) -> Bool {
        lumitextCacheLock.lock()
        let cached = lumitextFamilyAvailable[family]
        lumitextCacheLock.unlock()
        if let cached { return cached }
        let available = NSFontManager.shared.availableFontFamilies.contains(family)
        lumitextCacheLock.lock()
        lumitextFamilyAvailable[family] = available
        lumitextCacheLock.unlock()
        return available
    }

    /// Resolve family + weight + size via descriptor traits. `Font.custom(...)
    /// .weight(...)` silently ignores the weight for many families; descriptor
    /// matching picks the actual face (e.g. "Helvetica Neue" + bold →
    /// HelveticaNeue-Bold). Returns nil when the family isn't installed in this
    /// process (the saver's sandbox may differ from the host) so the caller can
    /// fall back.
    static func lumitextFont(family: String, weight: NSFont.Weight, size: CGFloat) -> NSFont? {
        guard lumitextFamilyIsAvailable(family) else { return nil }
        let key = "\(family)|\(weight.rawValue)|\(size)"
        lumitextCacheLock.lock()
        let cached = lumitextFontCache[key]
        lumitextCacheLock.unlock()
        if let cached { return cached }
        let descriptor = NSFontDescriptor(fontAttributes: [
            .family: family,
            .traits: [NSFontDescriptor.TraitKey.weight: weight.rawValue],
        ])
        guard let font = NSFont(descriptor: descriptor, size: size) else { return nil }
        lumitextCacheLock.lock()
        if lumitextFontCache.count >= lumitextFontCacheCap { lumitextFontCache.removeAll() }
        lumitextFontCache[key] = font
        lumitextCacheLock.unlock()
        return font
    }
}
#endif

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
            // Scale is HEIGHT-only by design: width participates in wrapping
            // (text wraps at the container's right edge), not in type size, so
            // a narrow container wraps more instead of shrinking the glyphs —
            // matching how the same config behaves across screen aspects.
            // Degenerate widths during transient layout passes are safe: the
            // wrap width floors at 0 and .clipped() bounds the cost.
            let scale = max(geo.size.height, 1) / LumitextConfig.referenceHeight
            let size = config.fontSize * scale
            let spacing = config.lineSpacing * scale
            let alignment = Alignment(
                horizontal: config.horizontalAlignment.swiftUI,
                vertical: config.verticalAlignment.swiftUI
            )

            // Positioning happens via the Text's own full-size frame(alignment:)
            // below — the ZStack needs no alignment of its own (both children
            // fill it, so a ZStack alignment would be dead code).
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
