//
//  RenderingTests.swift
//  LumitextCoreTests
//
//  Non-gated coverage for LumitextRendering — the single shared renderer that
//  backs the WYSIWYG guarantee. The bridging logic here is pure and screenless,
//  so it runs in normal `swift test` (unlike the LUMITEXT_SNAPSHOT-gated
//  SnapshotGenerator); a regression mismapping a weight or alignment case must
//  not pass with a green suite.
//

import XCTest
import SwiftUI
@testable import LumitextCore

final class RenderingBridgeTests: XCTestCase {

    func testEveryFontWeightMapsToMatchingSwiftUIWeight() {
        let expected: [FontWeight: Font.Weight] = [
            .thin: .thin, .light: .light, .regular: .regular, .medium: .medium,
            .semibold: .semibold, .bold: .bold, .heavy: .heavy, .black: .black,
        ]
        for weight in FontWeight.allCases {
            XCTAssertEqual(weight.swiftUIWeight, expected[weight], "for \(weight)")
        }
    }

    func testEveryFontWeightMapsToMatchingNSFontWeight() {
        let expected: [FontWeight: NSFont.Weight] = [
            .thin: .thin, .light: .light, .regular: .regular, .medium: .medium,
            .semibold: .semibold, .bold: .bold, .heavy: .heavy, .black: .black,
        ]
        for weight in FontWeight.allCases {
            XCTAssertEqual(weight.nsWeight, expected[weight], "for \(weight)")
        }
    }

    func testHorizontalAlignmentBridges() {
        XCTAssertEqual(LumitextCore.HorizontalAlignment.leading.swiftUI, .leading)
        XCTAssertEqual(LumitextCore.HorizontalAlignment.center.swiftUI, .center)
        XCTAssertEqual(LumitextCore.HorizontalAlignment.trailing.swiftUI, .trailing)
        XCTAssertEqual(LumitextCore.HorizontalAlignment.leading.textAlignment, .leading)
        XCTAssertEqual(LumitextCore.HorizontalAlignment.center.textAlignment, .center)
        XCTAssertEqual(LumitextCore.HorizontalAlignment.trailing.textAlignment, .trailing)
    }

    func testVerticalAlignmentBridges() {
        XCTAssertEqual(LumitextCore.VerticalAlignment.top.swiftUI, .top)
        XCTAssertEqual(LumitextCore.VerticalAlignment.center.swiftUI, .center)
        XCTAssertEqual(LumitextCore.VerticalAlignment.bottom.swiftUI, .bottom)
    }

    /// swiftUIColor is the bridge the renderer actually DRAWS with — pin its
    /// sRGB components and opacity via AppKit resolution (NSColor(Color) keeps
    /// the underlying color values for a concrete sRGB color).
    func testSwiftUIColorPreservesComponentsAndOpacity() throws {
        let original = RGBAColor(red: 0.21, green: 0.47, blue: 0.83, alpha: 0.6)
        let resolved = try XCTUnwrap(NSColor(original.swiftUIColor).usingColorSpace(.sRGB))
        XCTAssertEqual(Double(resolved.redComponent), original.red, accuracy: 0.001)
        XCTAssertEqual(Double(resolved.greenComponent), original.green, accuracy: 0.001)
        XCTAssertEqual(Double(resolved.blueComponent), original.blue, accuracy: 0.001)
        XCTAssertEqual(Double(resolved.alphaComponent), original.alpha, accuracy: 0.001)
    }

    /// The color-picker write path is RGBAColor → NSColor → RGBAColor; a colorspace
    /// regression there silently mis-saves every picked color.
    func testRGBAColorNSColorRoundTrip() {
        let original = RGBAColor(red: 0.21, green: 0.47, blue: 0.83, alpha: 0.6)
        let roundTripped = RGBAColor(original.nsColor)
        XCTAssertEqual(roundTripped.red, original.red, accuracy: 0.001)
        XCTAssertEqual(roundTripped.green, original.green, accuracy: 0.001)
        XCTAssertEqual(roundTripped.blue, original.blue, accuracy: 0.001)
        XCTAssertEqual(roundTripped.alpha, original.alpha, accuracy: 0.001)
    }

    /// Non-sRGB inputs (the picker can hand back Display P3 or catalog colors)
    /// must convert, not crash or zero out.
    func testRGBAColorInitFromNonSRGBColor() {
        let p3 = NSColor(displayP3Red: 0.5, green: 0.5, blue: 0.5, alpha: 1)
        let converted = RGBAColor(p3)
        XCTAssertGreaterThan(converted.red, 0.3)
        XCTAssertLessThan(converted.red, 0.7)
        XCTAssertEqual(converted.alpha, 1)
    }

    /// Pattern colors have NO RGB components — usingColorSpace returns nil and
    /// touching redComponent on the original TRAPS. The bridge must fall back
    /// to a safe opaque color, never crash, whatever exotic color arrives.
    func testRGBAColorInitFromPatternColorDoesNotCrash() {
        let image = NSImage(size: NSSize(width: 2, height: 2), flipped: false) { rect in
            NSColor.red.setFill()
            rect.fill()
            return true
        }
        let pattern = NSColor(patternImage: image)
        let converted = RGBAColor(pattern)
        XCTAssertEqual(converted.alpha, 1, "fallback must be opaque")
        for channel in [converted.red, converted.green, converted.blue] {
            XCTAssertTrue((0...1).contains(channel))
        }
    }

    // MARK: - Saver-readable font-path policy (drives the divergence warning)

    func testFontPathPolicyAcceptsSystemFontLocations() {
        XCTAssertFalse(FontPathPolicy.mayNotResolveInSaver(fontAt: "/System/Library/Fonts/SFNS.ttf"))
        XCTAssertFalse(FontPathPolicy.mayNotResolveInSaver(fontAt: "/Library/Fonts/Custom.otf"))
    }

    func testFontPathPolicyFlagsEverythingElse() {
        XCTAssertTrue(FontPathPolicy.mayNotResolveInSaver(
            fontAt: NSHomeDirectory() + "/Library/Fonts/UserFont.ttf"))
        XCTAssertTrue(FontPathPolicy.mayNotResolveInSaver(
            fontAt: "/Applications/SomeApp.app/Contents/Resources/Bundled.otf"))
        XCTAssertTrue(FontPathPolicy.mayNotResolveInSaver(
            fontAt: "/Volumes/Network/Fonts/Remote.ttf"))
    }

    /// The memoized availability cache must be invalidatable (fonts can be
    /// (un)installed mid-session) and behave identically after a reset.
    func testFamilyCacheInvalidationKeepsResolutionConsistent() {
        XCTAssertNil(NSFont.lumitextFont(family: "No Such Family 字体", weight: .bold, size: 24))
        NSFont.lumitextInvalidateFamilyCache()
        XCTAssertNil(NSFont.lumitextFont(family: "No Such Family 字体", weight: .bold, size: 24))
        XCTAssertNotNil(NSFont.lumitextFont(family: "Helvetica", weight: .regular, size: 12))
    }

    // MARK: - Weighted face resolution (Font.custom().weight() ignores many families)

    func testLumitextFontResolvesInstalledFamilyWithWeight() throws {
        // Helvetica ships with every macOS and has a real bold face.
        let font = try XCTUnwrap(NSFont.lumitextFont(family: "Helvetica", weight: .bold, size: 24))
        XCTAssertEqual(font.pointSize, 24)
        let traits = font.fontDescriptor.object(forKey: .traits) as? [NSFontDescriptor.TraitKey: Any]
        let weight = traits?[.weight] as? CGFloat ?? 0
        XCTAssertGreaterThan(weight, NSFont.Weight.regular.rawValue,
                             "bold request should resolve a heavier-than-regular face")
    }

    func testLumitextFontReturnsNilForUnknownFamily() {
        XCTAssertNil(NSFont.lumitextFont(family: "No Such Family 字体", weight: .bold, size: 24))
    }
}

/// One deterministic rasterization so the actual view body executes in CI.
/// (The full visual sample set stays in the gated SnapshotGenerator.)
final class RenderingSmokeTests: XCTestCase {

    /// A full-block glyph (U+2588) at a huge size guarantees the CENTER pixel
    /// lands inside the glyph while the corner stays pure background — so "text
    /// is drawn" and "background fills the frame" are both falsifiable without
    /// depending on font metrics or exact color management.
    @MainActor
    func testRendererDrawsTextAndFillsBackground() throws {
        var blocky = LumitextConfig.default
        blocky.text = "█"
        blocky.fontSize = 800
        blocky.textColor = .white

        let textCenter = try pixel(of: blocky, atCenter: true)
        let textCorner = try pixel(of: blocky, atCenter: false)

        var textless = blocky
        textless.text = ""
        let bgCenter = try pixel(of: textless, atCenter: true)

        // Text is drawn: the center is bright where the white glyph lands…
        XCTAssertGreaterThan(textCenter.brightnessComponent, 0.5, "glyph must be drawn at center")
        // …the corner stays dark, blue-dominant background…
        XCTAssertLessThan(textCorner.brightnessComponent, 0.5, "corner must stay background")
        XCTAssertGreaterThan(textCorner.blueComponent, textCorner.redComponent,
                             "deep navy must stay blue-dominant")
        // …and with no text, the background fills the center too.
        XCTAssertLessThan(bgCenter.brightnessComponent, 0.5, "textless render must be all background")
    }

    /// The fallback chain the sandboxed saver actually hits: a config naming a
    /// family this process can't resolve must still render (system-font
    /// fallback), never crash or produce an empty image.
    @MainActor
    func testUnknownFontFamilyStillRenders() throws {
        var config = LumitextConfig.default
        config.fontFamily = "No Such Family 字体"
        config.text = "█"
        config.fontSize = 800
        config.textColor = .white

        let center = try pixel(of: config, atCenter: true)
        XCTAssertGreaterThan(center.brightnessComponent, 0.5,
                             "glyph must still be drawn via the fallback font")
    }

    /// And an installed family resolves through the descriptor path.
    @MainActor
    func testInstalledFontFamilyRenders() throws {
        var config = LumitextConfig.default
        config.fontFamily = "Helvetica"
        config.text = "█"
        config.fontSize = 800
        config.textColor = .white

        let center = try pixel(of: config, atCenter: true)
        XCTAssertGreaterThan(center.brightnessComponent, 0.5)
    }

    /// THE WYSIWYG contract: typography scales by container HEIGHT, so the
    /// same config at 2x the height must paint a ~2x-taller glyph. A mutant
    /// that fixes scale at 1.0 (or scales by width) fails this.
    @MainActor
    func testTypographyScalesProportionallyWithHeight() throws {
        var config = LumitextConfig.default
        config.text = "█"
        config.fontSize = 400
        config.textColor = .white

        let small = try brightRowCount(of: config, size: CGSize(width: 192, height: 120))
        let large = try brightRowCount(of: config, size: CGSize(width: 384, height: 240))
        XCTAssertGreaterThan(small, 0, "glyph must be visible at the small size")
        let ratio = Double(large) / Double(small)
        XCTAssertEqual(ratio, 2.0, accuracy: 0.35,
                       "glyph height must track container height (got ratio \(ratio))")
    }

    /// The .clipped() safety bound: an absurd font size must never paint
    /// outside the container. Removing .clipped() lets the glyph cover the
    /// corner and fails this.
    @MainActor
    func testOversizedGlyphIsClippedToContainer() throws {
        var config = LumitextConfig.default
        config.text = "█"
        config.fontSize = 2000
        config.textColor = .white

        let corner = try pixel(of: config, atCenter: false)
        XCTAssertLessThan(corner.brightnessComponent, 0.5,
                          "the frame corner must stay background even at fontSize 2000")
    }

    /// Rows containing at least one bright (glyph) pixel — a font-metric-free
    /// proxy for the rendered glyph's height.
    @MainActor
    private func brightRowCount(of config: LumitextConfig, size: CGSize) throws -> Int {
        let renderer = ImageRenderer(
            content: LumitextTextView(config: config)
                .frame(width: size.width, height: size.height)
        )
        renderer.proposedSize = ProposedViewSize(size)
        guard let nsImage = renderer.nsImage else {
            throw XCTSkip("ImageRenderer produced no image — headless/no-WindowServer session; pixel tests need a GUI login")
        }
        let tiff = try XCTUnwrap(nsImage.tiffRepresentation)
        let rep = try XCTUnwrap(NSBitmapImageRep(data: tiff))
        var rows = 0
        for y in 0..<rep.pixelsHigh {
            for x in 0..<rep.pixelsWide {
                if let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB),
                   c.brightnessComponent > 0.5 {
                    rows += 1
                    break
                }
            }
        }
        return rows
    }

    @MainActor
    private func pixel(of config: LumitextConfig, atCenter: Bool) throws -> NSColor {
        let size = CGSize(width: 192, height: 120)
        let renderer = ImageRenderer(
            content: LumitextTextView(config: config)
                .frame(width: size.width, height: size.height)
        )
        renderer.proposedSize = ProposedViewSize(size)
        guard let nsImage = renderer.nsImage else {
            throw XCTSkip("ImageRenderer produced no image — headless/no-WindowServer session; pixel tests need a GUI login")
        }
        let tiff = try XCTUnwrap(nsImage.tiffRepresentation)
        let rep = try XCTUnwrap(NSBitmapImageRep(data: tiff))
        XCTAssertGreaterThan(rep.pixelsWide, 0)
        XCTAssertGreaterThan(rep.pixelsHigh, 0)
        let (x, y) = atCenter ? (rep.pixelsWide / 2, rep.pixelsHigh / 2) : (1, 1)
        let color = try XCTUnwrap(rep.colorAt(x: x, y: y))
        return try XCTUnwrap(color.usingColorSpace(.sRGB))
    }
}
