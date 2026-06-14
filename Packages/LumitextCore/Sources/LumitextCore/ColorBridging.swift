//
//  ColorBridging.swift
//  LumitextCore
//
//  Bridges the UI-free Codable RGBAColor to SwiftUI's Color and AppKit's NSColor.
//  Kept out of the model file so LumitextConfig stays pure Foundation.
//

import SwiftUI

#if canImport(AppKit)
import AppKit
#endif

public extension RGBAColor {
    var swiftUIColor: Color {
        Color(.sRGB, red: red, green: green, blue: blue, opacity: alpha)
    }

    #if canImport(AppKit)
    var nsColor: NSColor {
        NSColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
    }

    init(_ nsColor: NSColor) {
        // usingColorSpace(_:) returns nil for pattern/catalog colors; reading
        // redComponent off such a color would trap. Try a second RGB conversion,
        // then fall back to opaque black — an exotic picker color must never crash.
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
