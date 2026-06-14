//
//  FontCatalog.swift
//  Lumitext
//
//  Detects families whose font file lives OUTSIDE the system-wide locations a
//  sandboxed process can read. The non-sandboxed host (and thus the live preview)
//  can render fonts from anywhere — the user's home folder, an app's own
//  bundle/container, network mounts — but the saver's sandbox only reaches
//  /System/Library and /Library/Fonts, so for every other origin it silently falls
//  back to the system font. ConfigPanel shows a warning for exactly that class of
//  fonts instead of letting WYSIWYG silently diverge.
//

import Foundation
import CoreText
import LumitextCore

@MainActor
enum FontCatalog {
    private static var divergenceCache: [String: Bool] = [:]

    /// Forget cached verdicts — fonts can be (un)installed mid-session; the host
    /// calls this whenever its family list changes.
    static func invalidate() {
        divergenceCache.removeAll()
    }

    static func mayNotResolveInSaver(_ family: String) -> Bool {
        guard !family.isEmpty else { return false }   // system font: always resolves
        if let cached = divergenceCache[family] { return cached }
        var result = false
        let query = CTFontDescriptorCreateWithAttributes(
            [kCTFontFamilyNameAttribute: family] as CFDictionary)
        if let matched = CTFontDescriptorCreateMatchingFontDescriptor(query, nil),
           let cfURL = CTFontDescriptorCopyAttribute(matched, kCTFontURLAttribute),
           let url = cfURL as? URL {
            // Resolve symlinks so a planted/aliased path can't dodge the check;
            // the path policy itself lives in Core where it's tested.
            let path = url.standardizedFileURL.resolvingSymlinksInPath().path
            result = FontPathPolicy.mayNotResolveInSaver(fontAt: path)
        }
        // No URL resolved → the HOST can't render it either, so preview and saver
        // agree (both fall back) — no divergence to warn about.
        divergenceCache[family] = result
        return result
    }
}
