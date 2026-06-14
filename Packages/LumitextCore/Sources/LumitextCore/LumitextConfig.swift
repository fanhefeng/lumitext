//
//  LumitextConfig.swift
//  LumitextCore
//
//  The single source of truth that flows host app → /Users/Shared/Lumitext → saver.
//  Pure Foundation (no UI) so it is trivially testable and Codable. All decoding
//  is forward/backward compatible: every field is optional-with-default and unknown
//  JSON keys are ignored, so an older saver can read a newer host's config (and vice
//  versa) without crashing — only `schemaVersion` gates any future hard migration.
//

import Foundation

/// Codable RGBA color in the 0...1 range. Stored as plain numbers so the JSON is
/// portable and human-inspectable; UI conversions live in LumitextRendering.swift.
public struct RGBAColor: Codable, Equatable, Sendable {
    // Channels clamp on EVERY mutation (didSet doesn't fire during init, which
    // keeps its own explicit clamps) so direct in-memory assignment can't
    // smuggle an out-of-gamut or non-finite value past the model boundary —
    // the same philosophy as LumitextConfig.text.
    public var red: Double { didSet { red = Self.clampChannel(red) } }
    public var green: Double { didSet { green = Self.clampChannel(green) } }
    public var blue: Double { didSet { blue = Self.clampChannel(blue) } }
    public var alpha: Double { didSet { alpha = Self.clampChannel(alpha) } }

    /// Valid color range; NaN/±inf collapse to 0 — a hand-edited/corrupt JSON
    /// or a stray computation can't produce values that misrender.
    private static func clampChannel(_ v: Double) -> Double {
        v.isFinite ? min(max(v, 0), 1) : 0
    }

    public init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = Self.clampChannel(red)
        self.green = Self.clampChannel(green)
        self.blue = Self.clampChannel(blue)
        self.alpha = Self.clampChannel(alpha)
    }

    public static let white = RGBAColor(red: 1, green: 1, blue: 1)
    public static let black = RGBAColor(red: 0, green: 0, blue: 0)
    /// Default backdrop: deep navy, matching the app's visual identity.
    public static let defaultBackground = RGBAColor(red: 0.06, green: 0.08, blue: 0.16)

    /// Approximate equality at 8-bit display precision (~1/255 per channel).
    /// Exact `==` is too strict once a color round-trips through AppKit color
    /// conversion (e.g. the ColorPicker write path), whose sub-display-precision
    /// float drift would otherwise make "is this preset applied?" checks flicker
    /// off even though the rendered color is identical.
    public func isApproximately(_ other: RGBAColor, tolerance: Double = 0.004) -> Bool {
        abs(red - other.red) <= tolerance &&
        abs(green - other.green) <= tolerance &&
        abs(blue - other.blue) <= tolerance &&
        abs(alpha - other.alpha) <= tolerance
    }

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
    /// The gate is wired in ConfigStore.loadResult(): a config claiming a NEWER
    /// version than this build understands is treated as a read failure rather
    /// than silently misrendered. Additive fields never bump this (decoding is
    /// tolerant via decodeIfPresent).
    public var schemaVersion: Int

    /// Clamped on EVERY mutation, not just init/decode: the host's TextEditor
    /// binds directly to this property, so a giant paste would otherwise bypass
    /// the text budgets entirely — full-string layout on each preview render and
    /// a megabyte config.json until the next relaunch re-clamped it. (Assigning
    /// inside didSet does not re-trigger the observer; init assignments don't
    /// fire it at all, which is why init/decode keep their explicit clamps.)
    public var text: String {
        didSet {
            let clamped = LumitextConfig.clampText(text)
            if clamped != text { text = clamped }
        }
    }

    /// Empty string means "system font". Otherwise an installed family name
    /// (e.g. "Helvetica Neue"). The saver resolves it in its own sandbox; if the
    /// family is unavailable there, rendering falls back to the system font.
    public var fontFamily: String
    public var fontWeight: FontWeight

    /// Point size measured against a 1080-point-tall reference screen. The renderer
    /// scales by (actualHeight / 1080) so the same config looks proportionally
    /// identical on any display and in the small WYSIWYG preview. See
    /// LumitextTextView in LumitextRendering.swift.
    ///
    /// Clamped on EVERY mutation, like `text`/`backgroundColor` — init/decode keep
    /// their own explicit clamps (didSet doesn't fire there). Without this, the
    /// renderer's "never a NaN/out-of-range size" guarantee would rest on every UI
    /// call site remembering to clamp; that's the call-site coincidence these
    /// observers exist to eliminate.
    public var fontSize: Double {
        didSet {
            let clamped = LumitextConfig.clampFontSize(fontSize)
            if clamped != fontSize { fontSize = clamped }
        }
    }

    public var textColor: RGBAColor
    /// Opaque on EVERY ingress path — init, decode, AND mutation: the host's
    /// ColorPicker and presets bind directly to this property, so the didSet
    /// enforces opacity rather than every call site having to remember to.
    public var backgroundColor: RGBAColor {
        didSet {
            let opaqued = LumitextConfig.opaque(backgroundColor)
            if opaqued != backgroundColor { backgroundColor = opaqued }
        }
    }

    public var horizontalAlignment: HorizontalAlignment
    public var verticalAlignment: VerticalAlignment

    /// Line spacing in reference points (added between wrapped/explicit lines).
    /// Clamped on every mutation for the same reason as `fontSize` above.
    public var lineSpacing: Double {
        didSet {
            let clamped = LumitextConfig.clampLineSpacing(lineSpacing)
            if clamped != lineSpacing { lineSpacing = clamped }
        }
    }

    public init(
        schemaVersion: Int = LumitextConfig.currentSchemaVersion,
        text: String = "Hello, Lumitext",
        fontFamily: String = "",
        fontWeight: FontWeight = .semibold,
        fontSize: Double = LumitextConfig.fallbackFontSize,
        textColor: RGBAColor = .white,
        backgroundColor: RGBAColor = .defaultBackground,
        horizontalAlignment: HorizontalAlignment = .center,
        verticalAlignment: VerticalAlignment = .center,
        lineSpacing: Double = 8
    ) {
        self.schemaVersion = schemaVersion
        self.text = LumitextConfig.clampText(text)
        self.fontFamily = fontFamily
        self.fontWeight = fontWeight
        self.fontSize = LumitextConfig.clampFontSize(fontSize)
        self.textColor = textColor
        self.backgroundColor = LumitextConfig.opaque(backgroundColor)
        self.horizontalAlignment = horizontalAlignment
        self.verticalAlignment = verticalAlignment
        self.lineSpacing = LumitextConfig.clampLineSpacing(lineSpacing)
    }

    /// Keep the renderer safe from corrupt/hand-edited values (0, negative, NaN, absurd).
    public static let fontSizeRange: ClosedRange<Double> = 1...2000
    /// Non-finite fallback. A named constant (not a free literal) shared with the
    /// init default below, so the "non-finite collapses to the default" contract
    /// can't silently drift. (Deliberately NOT LumitextConfig.default.fontSize —
    /// clampFontSize runs inside init, so referencing the static `default` here
    /// would re-enter its own lazy initialization.)
    /// Public because the `init` default argument above references it (a public
    /// initializer's defaults can't see internal symbols).
    public static let fallbackFontSize: Double = 120
    static func clampFontSize(_ v: Double) -> Double {
        v.isFinite ? min(max(v, fontSizeRange.lowerBound), fontSizeRange.upperBound) : fallbackFontSize
    }
    public static let lineSpacingRange: ClosedRange<Double> = 0...1000
    static func clampLineSpacing(_ v: Double) -> Double {
        v.isFinite ? min(max(v, lineSpacingRange.lowerBound), lineSpacingRange.upperBound) : 0
    }

    /// The "comfortable" slider travel for each field — a usable everyday range,
    /// narrower than the hard model range above (which also admits hand-edited
    /// extremes). The UI slider rides these; the numeric field and clamps ride
    /// the full range. Lives here, next to the hard ranges, so the two can't
    /// drift across the model/UI boundary.
    public static let fontSizeComfortRange: ClosedRange<Double> = 24...480
    public static let lineSpacingComfortRange: ClosedRange<Double> = 0...100

    /// The screensaver background is always opaque: the engine draws black behind
    /// the view and the preview draws a window, so a translucent background would
    /// render DIFFERENTLY in each — and the contrast warning already treats it as
    /// opaque. Enforced at the model boundary (init + decode + the property's
    /// own didSet, so direct mutation can't bypass it either).
    static func opaque(_ c: RGBAColor) -> RGBAColor {
        RGBAColor(red: c.red, green: c.green, blue: c.blue, alpha: 1)
    }

    /// Generous ceilings for screensaver text. Every numeric field is clamped at
    /// the boundary; the text gets the same treatment so a hand-edited or hostile
    /// config.json can't feed the renderer megabytes of layout work. Three
    /// independent budgets, because each bounds a different cost:
    /// - grapheme count (what the user perceives as "characters"),
    /// - unicode-scalar count (a single grapheme can be a huge ZWJ cluster),
    /// - line count (SwiftUI lays out EVERY line before .clipped() discards it,
    ///   so 2000 newlines would be 2000 measured lines on each render).
    static let maxTextLength = 2000
    static let maxTextLines = 200
    static let maxTextScalars = maxTextLength * 4
    static func clampText(_ v: String) -> String {
        var s = v.count <= maxTextLength ? v : String(v.prefix(maxTextLength))
        if s.unicodeScalars.count > maxTextScalars {
            // Cut on a GRAPHEME boundary: keep the longest whole-cluster prefix
            // whose total scalar count fits the budget. A raw scalar prefix
            // could tear the final cluster (invalid text), and unconditionally
            // dropping the last grapheme would discard an intact character
            // when the cut happens to land on a boundary.
            var scalarCount = 0
            var end = s.startIndex
            for i in s.indices {
                scalarCount += s[i].unicodeScalars.count
                if scalarCount > maxTextScalars { break }
                end = s.index(after: i)
            }
            s = String(s[..<end])
        }
        if s.contains("\n") {
            let lines = s.split(separator: "\n", omittingEmptySubsequences: false)
            if lines.count > maxTextLines {
                s = lines.prefix(maxTextLines).joined(separator: "\n")
            }
        }
        return s
    }

    /// Clamp AND report whether anything was removed. The truncation signal
    /// belongs on the clamp itself: otherwise every write site (editor binding,
    /// preset, config load) has to re-derive "was it shortened?" from a get/set
    /// diff, and only the editor binding actually does — so a programmatic
    /// change that truncates passes silently. Single source of truth here.
    public static func clampTextReportingTruncation(_ v: String) -> (text: String, truncated: Bool) {
        let clamped = clampText(v)
        return (clamped, clamped != v)
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
        text = LumitextConfig.clampText(try c.decodeIfPresent(String.self, forKey: .text) ?? d.text)
        fontFamily = try c.decodeIfPresent(String.self, forKey: .fontFamily) ?? d.fontFamily
        fontSize = LumitextConfig.clampFontSize(try c.decodeIfPresent(Double.self, forKey: .fontSize) ?? d.fontSize)
        textColor = try c.decodeIfPresent(RGBAColor.self, forKey: .textColor) ?? d.textColor
        backgroundColor = LumitextConfig.opaque(try c.decodeIfPresent(RGBAColor.self, forKey: .backgroundColor) ?? d.backgroundColor)
        lineSpacing = LumitextConfig.clampLineSpacing(try c.decodeIfPresent(Double.self, forKey: .lineSpacing) ?? d.lineSpacing)
        // Enums: decode the raw string and map tolerantly. A raw enum decode would
        // THROW on an unknown future value; decoding the string and using
        // init(rawValue:) lets an unrecognized value fall back to the default.
        fontWeight = FontWeight(rawValue: try c.decodeIfPresent(String.self, forKey: .fontWeight) ?? "") ?? d.fontWeight
        horizontalAlignment = HorizontalAlignment(rawValue: try c.decodeIfPresent(String.self, forKey: .horizontalAlignment) ?? "") ?? d.horizontalAlignment
        verticalAlignment = VerticalAlignment(rawValue: try c.decodeIfPresent(String.self, forKey: .verticalAlignment) ?? "") ?? d.verticalAlignment
    }
}
