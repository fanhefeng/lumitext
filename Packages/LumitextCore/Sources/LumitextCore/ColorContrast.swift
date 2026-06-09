//
//  ColorContrast.swift
//  LumitextCore
//
//  WCAG relative-luminance contrast between the configured text and background
//  colors, used to warn before the user saves an invisible-text combination.
//  Text alpha is composited over the background first — a half-transparent white
//  on white is exactly the case a naive check misses.
//
//  Pure math on the UI-free model, so it lives in Core (and is unit-tested).
//

import Foundation

/// WCAG 2.x contrast ratio (1...21) between the text color (alpha-composited
/// over the background) and the opaque background.
public func contrastRatio(text: RGBAColor, background: RGBAColor) -> Double {
    let a = text.alpha
    let composited = (
        r: text.red * a + background.red * (1 - a),
        g: text.green * a + background.green * (1 - a),
        b: text.blue * a + background.blue * (1 - a)
    )
    let lt = relativeLuminance(r: composited.r, g: composited.g, b: composited.b)
    let lb = relativeLuminance(r: background.red, g: background.green, b: background.blue)
    let (hi, lo) = (max(lt, lb), min(lt, lb))
    return (hi + 0.05) / (lo + 0.05)
}

/// WCAG relative luminance of an opaque sRGB color (0 = black, 1 = white).
public func relativeLuminance(r: Double, g: Double, b: Double) -> Double {
    func linearize(_ c: Double) -> Double {
        c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
    }
    return 0.2126 * linearize(r) + 0.7152 * linearize(g) + 0.0722 * linearize(b)
}

public extension RGBAColor {
    /// Perceptual lightness of the color, ignoring alpha (for picking a legible
    /// overlay tint on top of this color).
    var isLight: Bool {
        relativeLuminance(r: red, g: green, b: blue) > 0.5
    }
}
