//
//  LumitextConfig.swift
//  LumitextCore
//
//  The single source of truth that flows host app → App Group container → saver.
//  Pure Foundation (no UI) so it is trivially testable and Codable. All decoding
//  is forward/backward compatible: every field is optional-with-default and unknown
//  JSON keys are ignored, so an older saver can read a newer host's config (and vice
//  versa) without crashing — only `schemaVersion` gates any future hard migration.
//

import Foundation

/// Codable RGBA color in the 0...1 range. Stored as plain numbers so the JSON is
/// portable and human-inspectable; UI conversions live in LumitextRendering.swift.
public struct RGBAColor: Codable, Equatable, Sendable {
    public var red: Double
    public var green: Double
    public var blue: Double
    public var alpha: Double

    public init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        // Clamp to a valid color range so a hand-edited/corrupt JSON can't produce
        // out-of-gamut values that misrender. NaN collapses to 0.
        func clamp(_ v: Double) -> Double { v.isFinite ? min(max(v, 0), 1) : 0 }
        self.red = clamp(red)
        self.green = clamp(green)
        self.blue = clamp(blue)
        self.alpha = clamp(alpha)
    }

    public static let white = RGBAColor(red: 1, green: 1, blue: 1)
    public static let black = RGBAColor(red: 0, green: 0, blue: 0)
    /// Default backdrop: deep navy, matching the app's visual identity.
    public static let defaultBackground = RGBAColor(red: 0.06, green: 0.08, blue: 0.16)

    private enum CodingKeys: String, CodingKey { case red, green, blue, alpha }

    // Route decoding through the clamping init so persisted/edited values stay valid.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            red: try c.decodeIfPresent(Double.self, forKey: .red) ?? 0,
            green: try c.decodeIfPresent(Double.self, forKey: .green) ?? 0,
            blue: try c.decodeIfPresent(Double.self, forKey: .blue) ?? 0,
            alpha: try c.decodeIfPresent(Double.self, forKey: .alpha) ?? 1
        )
    }
}

/// Horizontal placement of the text block within the screen.
public enum HorizontalAlignment: String, Codable, CaseIterable, Sendable {
    case leading, center, trailing
}

/// Vertical placement of the text block within the screen.
public enum VerticalAlignment: String, Codable, CaseIterable, Sendable {
    case top, center, bottom
}

/// Font weight, decoupled from AppKit/SwiftUI so the model stays UI-free.
public enum FontWeight: String, Codable, CaseIterable, Sendable {
    case thin, light, regular, medium, semibold, bold, heavy, black
}

public struct LumitextConfig: Codable, Equatable, Sendable {
    /// Bump only for breaking changes that need migration code. v1 = initial.
    public var schemaVersion: Int

    public var text: String

    /// Empty string means "system font". Otherwise an installed family name
    /// (e.g. "Helvetica Neue"). The saver resolves it in its own sandbox; if the
    /// family is unavailable there, rendering falls back to the system font.
    public var fontFamily: String
    public var fontWeight: FontWeight

    /// Point size measured against a 1080-point-tall reference screen. The renderer
    /// scales by (actualHeight / 1080) so the same config looks proportionally
    /// identical on any display and in the small WYSIWYG preview. See LumitextLayout.
    public var fontSize: Double

    public var textColor: RGBAColor
    public var backgroundColor: RGBAColor

    public var horizontalAlignment: HorizontalAlignment
    public var verticalAlignment: VerticalAlignment

    /// Line spacing in reference points (added between wrapped/explicit lines).
    public var lineSpacing: Double

    public init(
        schemaVersion: Int = LumitextConfig.currentSchemaVersion,
        text: String = "Hello, Lumitext",
        fontFamily: String = "",
        fontWeight: FontWeight = .semibold,
        fontSize: Double = 120,
        textColor: RGBAColor = .white,
        backgroundColor: RGBAColor = .defaultBackground,
        horizontalAlignment: HorizontalAlignment = .center,
        verticalAlignment: VerticalAlignment = .center,
        lineSpacing: Double = 8
    ) {
        self.schemaVersion = schemaVersion
        self.text = text
        self.fontFamily = fontFamily
        self.fontWeight = fontWeight
        self.fontSize = LumitextConfig.clampFontSize(fontSize)
        self.textColor = textColor
        self.backgroundColor = backgroundColor
        self.horizontalAlignment = horizontalAlignment
        self.verticalAlignment = verticalAlignment
        self.lineSpacing = LumitextConfig.clampLineSpacing(lineSpacing)
    }

    /// Keep the renderer safe from corrupt/hand-edited values (0, negative, NaN, absurd).
    public static let fontSizeRange: ClosedRange<Double> = 1...2000
    static func clampFontSize(_ v: Double) -> Double {
        v.isFinite ? min(max(v, fontSizeRange.lowerBound), fontSizeRange.upperBound) : 120
    }
    static func clampLineSpacing(_ v: Double) -> Double {
        v.isFinite ? min(max(v, 0), 1000) : 0
    }

    public static let currentSchemaVersion = 1

    /// The configuration shown before the user has saved anything.
    public static let `default` = LumitextConfig()

    /// The reference screen height (points) that `fontSize`/`lineSpacing` are
    /// expressed against. Rendering scales relative to this so output is
    /// resolution-independent and the preview is a faithful miniature.
    public static let referenceHeight: Double = 1080

    // MARK: - Forward/backward-compatible decoding

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, text, fontFamily, fontWeight, fontSize
        case textColor, backgroundColor, horizontalAlignment, verticalAlignment, lineSpacing
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = LumitextConfig.default
        // decodeIfPresent everywhere → missing keys fall back to defaults instead of throwing.
        schemaVersion = try c.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? d.schemaVersion
        text = try c.decodeIfPresent(String.self, forKey: .text) ?? d.text
        fontFamily = try c.decodeIfPresent(String.self, forKey: .fontFamily) ?? d.fontFamily
        fontSize = LumitextConfig.clampFontSize(try c.decodeIfPresent(Double.self, forKey: .fontSize) ?? d.fontSize)
        textColor = try c.decodeIfPresent(RGBAColor.self, forKey: .textColor) ?? d.textColor
        backgroundColor = try c.decodeIfPresent(RGBAColor.self, forKey: .backgroundColor) ?? d.backgroundColor
        lineSpacing = LumitextConfig.clampLineSpacing(try c.decodeIfPresent(Double.self, forKey: .lineSpacing) ?? d.lineSpacing)
        // Enums: decode the raw string and map tolerantly. A raw enum decode would
        // THROW on an unknown future value; decoding the string and using
        // init(rawValue:) lets an unrecognized value fall back to the default.
        fontWeight = FontWeight(rawValue: try c.decodeIfPresent(String.self, forKey: .fontWeight) ?? "") ?? d.fontWeight
        horizontalAlignment = HorizontalAlignment(rawValue: try c.decodeIfPresent(String.self, forKey: .horizontalAlignment) ?? "") ?? d.horizontalAlignment
        verticalAlignment = VerticalAlignment(rawValue: try c.decodeIfPresent(String.self, forKey: .verticalAlignment) ?? "") ?? d.verticalAlignment
    }
}
