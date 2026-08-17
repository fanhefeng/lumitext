//
//  make-thumbnail.swift
//  Generates the System Settings thumbnail PNGs (107x65 @1x, 214x130 @2x)
//  for the saver appex. Works from any cwd:
//      swift scripts/make-thumbnail.swift
//
//  Visuals mirror make-appicon.swift (same glyph geometry and palette): indigo
//  vertical gradient, gold stroked geometric "A", cyan caret — so the saver's
//  list tile in System Settings matches the app icon.
//
//  Uses NSBitmapImageRep with explicit pixel dimensions so Retina backing
//  scale can't inflate the output (System Settings requires exact sizes).
//

import AppKit

// Anchor output to the repo root via this script's own location, so the script
// works regardless of the caller's cwd.
let repoRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()  // scripts/
    .deletingLastPathComponent()  // repo root
let outDir = repoRoot.appendingPathComponent("Saver/Assets.xcassets/thumbnail.imageset").path
try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)
let variants: [(w: Int, h: Int, name: String)] = [
    (107, 65, "thumbnail.png"),
    (214, 130, "thumbnail@2x.png"),
]

for v in variants {
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: v.w,
        pixelsHigh: v.h,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else { fatalError("could not create bitmap rep") }
    rep.size = NSSize(width: v.w, height: v.h)

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    let w = CGFloat(v.w)
    let h = CGFloat(v.h)
    let rect = NSRect(x: 0, y: 0, width: w, height: h)

    // Indigo vertical gradient, full bleed (same stops as the app icon).
    NSGradient(
        starting: NSColor(srgbRed: 0.310, green: 0.275, blue: 0.898, alpha: 1),  // #4F46E5
        ending: NSColor(srgbRed: 0.137, green: 0.106, blue: 0.439, alpha: 1)     // #231B70
    )!.draw(in: rect, angle: -90)

    // Glyph coordinates reuse make-appicon.swift's 1024-unit design grid (y down).
    // The A + caret cluster spans roughly x 250...795, y 255...785 in that grid;
    // scale it to ~2/3 of the thumbnail height and sit it just left of center so
    // it stays legible at System Settings list size.
    let cluster = NSRect(x: 250, y: 255, width: 545, height: 530)  // design units
    let scale = h * 0.68 / cluster.height
    let originX = w * 0.46 - cluster.midX * scale
    let originYTop = h * 0.5 - cluster.midY * scale
    func X(_ u: CGFloat) -> CGFloat { originX + u * scale }
    func Y(_ u: CGFloat) -> CGFloat { h - (originYTop + u * scale) }
    func L(_ d: CGFloat) -> CGFloat { d * scale }

    // Warm halo behind the glyph.
    let halo = NSGradient(colors: [
        NSColor(srgbRed: 1.0, green: 0.84, blue: 0.40, alpha: 0.30),  // #FFD666
        NSColor(srgbRed: 1.0, green: 0.84, blue: 0.40, alpha: 0.0),
    ])!
    let haloCenter = NSPoint(x: X(450), y: Y(480))
    halo.draw(fromCenter: haloCenter, radius: 0, toCenter: haloCenter, radius: L(560), options: [])

    // Geometric letter A: two legs with a soft apex, plus crossbar (icon geometry).
    let glyph = NSBezierPath()
    glyph.lineWidth = L(86)
    glyph.lineCapStyle = .round
    glyph.lineJoinStyle = .round
    glyph.move(to: NSPoint(x: X(296), y: Y(736)))
    glyph.line(to: NSPoint(x: X(452), y: Y(320)))
    glyph.curve(to: NSPoint(x: X(480), y: Y(320)),
                controlPoint1: NSPoint(x: X(461.3), y: Y(298.7)),
                controlPoint2: NSPoint(x: X(470.7), y: Y(298.7)))
    glyph.line(to: NSPoint(x: X(636), y: Y(736)))
    glyph.move(to: NSPoint(x: X(360), y: Y(592)))
    glyph.line(to: NSPoint(x: X(572), y: Y(592)))

    // Gold stroke with a soft glow (flat #F6B73C — the icon's gradient reads as
    // flat at this size anyway).
    NSGraphicsContext.current?.saveGraphicsState()
    let glow = NSShadow()
    glow.shadowColor = NSColor(srgbRed: 1.0, green: 0.80, blue: 0.35, alpha: 0.85)
    glow.shadowBlurRadius = h * 0.05
    glow.set()
    NSColor(srgbRed: 0.965, green: 0.718, blue: 0.235, alpha: 1).setStroke()  // #F6B73C
    glyph.stroke()
    NSGraphicsContext.current?.restoreGraphicsState()

    // Cyan caret with its own glow.
    NSGraphicsContext.current?.saveGraphicsState()
    let caretGlow = NSShadow()
    caretGlow.shadowColor = NSColor(srgbRed: 0.42, green: 0.96, blue: 0.93, alpha: 0.85)
    caretGlow.shadowBlurRadius = h * 0.04
    caretGlow.set()
    let caret = NSBezierPath(
        roundedRect: NSRect(x: X(716), y: Y(740), width: L(36), height: L(424)),
        xRadius: L(18), yRadius: L(18))
    NSColor(srgbRed: 0.42, green: 0.96, blue: 0.93, alpha: 1).setFill()  // #6BF5ED
    caret.fill()
    NSGraphicsContext.current?.restoreGraphicsState()

    NSGraphicsContext.restoreGraphicsState()

    guard let png = rep.representation(using: .png, properties: [:]) else {
        fatalError("could not encode png")
    }
    try! png.write(to: URL(fileURLWithPath: "\(outDir)/\(v.name)"))
    print("wrote \(outDir)/\(v.name) (\(v.w)x\(v.h))")
}
