//
//  FontResolution.swift
//  LumitextCore
//
//  Font weight bridging, the sandbox font-path policy, and the memoized NSFont
//  resolver shared by the renderer. Separated from the renderer view so the
//  caching and the (unit-tested) path policy stand on their own.
//

import SwiftUI

#if canImport(AppKit)
import AppKit
#endif

// MARK: - Weight bridging

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

// MARK: - Sandbox font-path policy

/// Which font-file locations the sandboxed saver appex can actually read.
/// Pure path policy (no font APIs) so the host's "this font may not show in
/// the screensaver" warning is unit-testable in Core.
public enum FontPathPolicy {
    /// Locations every sandboxed process can read fonts from. ~/Library/Fonts,
    /// app bundles/containers, and network mounts are NOT here — fonts there
    /// render in the non-sandboxed host but fall back to the system font in the saver.
    public static let saverReadablePrefixes = ["/System/Library/", "/Library/Fonts/"]

    public static func mayNotResolveInSaver(fontAt path: String) -> Bool {
        !saverReadablePrefixes.contains { path.hasPrefix($0) }
    }
}

// MARK: - Memoized NSFont resolver

#if canImport(AppKit)
public extension NSFont {
    /// `availableFontFamilies` walks the font registry — too expensive for the
    /// render path, which re-evaluates on every preview keystroke. Memoized per
    /// family name; the host calls `lumitextInvalidateFamilyCache()` when its
    /// family list changes.
    private static let lumitextCacheLock = NSLock()
    nonisolated(unsafe) private static var lumitextFamilyAvailable: [String: Bool] = [:]
    /// Resolved faces keyed by family|weight|size. The descriptor trait-match in
    /// `lumitextFont` is the per-call cost, and `body` re-resolves on every layout
    /// pass at a stable size — so cache the finished NSFont. Bounded: a live
    /// drag-resize sweeps many sizes, so clear past a cap rather than grow forever.
    nonisolated(unsafe) private static var lumitextFontCache: [String: NSFont] = [:]
    private static let lumitextFontCacheCap = 128

    /// Forget memoized availability and resolved faces — call when the installed
    /// font set may have changed, so a font installed/replaced mid-session starts
    /// rendering without a relaunch.
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
