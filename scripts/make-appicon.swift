//
//  make-appicon.swift
//  Generates the macOS AppIcon set: an indigo rounded-rect with a glowing
//  geometric "A" and a cyan caret — the product in one glyph. Works from any cwd:
//      swift scripts/make-appicon.swift
//
//  Draws the 1024 master with explicit pixel dimensions (Retina-safe), then
//  downscales to every required size. macOS icon artwork includes its own
//  rounded-rect shape with transparent margins (the system does not mask it).
//

import AppKit

// Anchor output to the repo root via this script's own location, so the script
// works regardless of the caller's cwd.
let repoRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()  // scripts/
    .deletingLastPathComponent()  // repo root
let outDir = repoRoot.appendingPathComponent("App/Assets.xcassets/AppIcon.appiconset").path
try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

func renderMaster(px: Int) -> NSBitmapImageRep {
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    ) else { fatalError("bitmap rep") }
    rep.size = NSSize(width: px, height: px)

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    defer { NSGraphicsContext.restoreGraphicsState() }

    let s = CGFloat(px)
    // Apple's macOS icon grid: ~824/1024 square, continuous-corner radius ~185.
    let inset = s * 0.098
    let body = NSRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
    let radius = s * 0.18
    let shape = NSBezierPath(roundedRect: body, xRadius: radius, yRadius: radius)

    // Design coordinates live on a 1024-unit grid (y down); map into the body.
    let b = s - inset * 2
    func X(_ u: CGFloat) -> CGFloat { inset + u / 1024 * b }
    func Y(_ v: CGFloat) -> CGFloat { s - (inset + v / 1024 * b) }
    func L(_ w: CGFloat) -> CGFloat { w / 1024 * b }

    // Indigo vertical gradient.
    NSGradient(colors: [
        NSColor(srgbRed: 0.310, green: 0.275, blue: 0.898, alpha: 1),  // #4F46E5
        NSColor(srgbRed: 0.137, green: 0.106, blue: 0.439, alpha: 1),  // #231B70
    ])!.draw(in: shape, angle: -90)

    NSGraphicsContext.current?.saveGraphicsState()
    shape.addClip()

    // Warm halo behind the glyph.
    let halo = NSGradient(colors: [
        NSColor(srgbRed: 1.0, green: 0.84, blue: 0.40, alpha: 0.32),   // #FFD666
        NSColor(srgbRed: 1.0, green: 0.84, blue: 0.40, alpha: 0.0),
    ])!
    let haloCenter = NSPoint(x: X(450), y: Y(480))
    halo.draw(fromCenter: haloCenter, radius: 0, toCenter: haloCenter, radius: L(560), options: [])

    // Geometric letter A: two legs with a soft apex, plus crossbar.
    // Quad control (466,288) converted to cubic below.
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

    // Pass 1: glow + solid base stroke.
    NSGraphicsContext.current?.saveGraphicsState()
    let glow = NSShadow()
    glow.shadowColor = NSColor(srgbRed: 1.0, green: 0.80, blue: 0.35, alpha: 0.85)
    glow.shadowBlurRadius = s * 0.038
    glow.set()
    NSColor(srgbRed: 0.965, green: 0.718, blue: 0.235, alpha: 1).setStroke()  // #F6B73C
    glyph.stroke()
    NSGraphicsContext.current?.restoreGraphicsState()

    // Pass 2: vertical gold gradient inside the stroked glyph.
    if let cg = NSGraphicsContext.current?.cgContext {
        cg.saveGState()
        let stroked = glyph.cgPath.copy(
            strokingWithWidth: L(86), lineCap: .round, lineJoin: .round, miterLimit: 10)
        cg.addPath(stroked)
        cg.clip()
        let colors = [
            NSColor(srgbRed: 1.0, green: 0.914, blue: 0.659, alpha: 1).cgColor,   // #FFE9A8
            NSColor(srgbRed: 0.965, green: 0.718, blue: 0.235, alpha: 1).cgColor, // #F6B73C
        ] as CFArray
        if let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                 colors: colors, locations: [0, 1]) {
            cg.drawLinearGradient(grad,
                                  start: CGPoint(x: X(466), y: Y(286)),
                                  end: CGPoint(x: X(466), y: Y(736)),
                                  options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        }
        cg.restoreGState()
    }

    // Cyan caret with its own glow.
    NSGraphicsContext.current?.saveGraphicsState()
    let caretGlow = NSShadow()
    caretGlow.shadowColor = NSColor(srgbRed: 0.42, green: 0.96, blue: 0.93, alpha: 0.85)
    caretGlow.shadowBlurRadius = s * 0.03
    caretGlow.set()
    let caret = NSBezierPath(
        roundedRect: NSRect(x: X(716), y: Y(740), width: L(36), height: L(424)),
        xRadius: L(18), yRadius: L(18))
    NSColor(srgbRed: 0.42, green: 0.96, blue: 0.93, alpha: 1).setFill()  // #6BF5ED
    caret.fill()
    NSGraphicsContext.current?.restoreGraphicsState()

    // Baseline.
    let base = NSBezierPath()
    base.lineWidth = L(12)
    base.lineCapStyle = .round
    base.move(to: NSPoint(x: X(232), y: Y(820)))
    base.line(to: NSPoint(x: X(792), y: Y(820)))
    NSColor(srgbRed: 0.545, green: 0.576, blue: 0.910, alpha: 0.55).setStroke()  // #8B93E8
    base.stroke()

    NSGraphicsContext.current?.restoreGraphicsState()  // shape clip
    return rep
}

func write(_ rep: NSBitmapImageRep, _ name: String) {
    guard let png = rep.representation(using: .png, properties: [:]) else { fatalError("png") }
    try! png.write(to: URL(fileURLWithPath: "\(outDir)/\(name)"))
    print("wrote \(outDir)/\(name)")
}

func downscale(_ master: NSBitmapImageRep, to px: Int) -> NSBitmapImageRep {
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    ) else { fatalError("bitmap rep") }
    rep.size = NSSize(width: px, height: px)
    NSGraphicsContext.saveGraphicsState()
    let ctx = NSGraphicsContext(bitmapImageRep: rep)
    ctx?.imageInterpolation = .high
    NSGraphicsContext.current = ctx
    let image = NSImage(size: master.size)
    image.addRepresentation(master)
    image.draw(in: NSRect(x: 0, y: 0, width: px, height: px))
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let master = renderMaster(px: 1024)
let sizes: [(Int, String)] = [
    (16, "icon_16.png"), (32, "icon_16@2x.png"),
    (32, "icon_32.png"), (64, "icon_32@2x.png"),
    (128, "icon_128.png"), (256, "icon_128@2x.png"),
    (256, "icon_256.png"), (512, "icon_256@2x.png"),
    (512, "icon_512.png"), (1024, "icon_512@2x.png"),
]
for (px, name) in sizes {
    write(px == 1024 ? master : downscale(master, to: px), name)
}

let contents = """
{
  "images" : [
    { "filename" : "icon_16.png", "idiom" : "mac", "scale" : "1x", "size" : "16x16" },
    { "filename" : "icon_16@2x.png", "idiom" : "mac", "scale" : "2x", "size" : "16x16" },
    { "filename" : "icon_32.png", "idiom" : "mac", "scale" : "1x", "size" : "32x32" },
    { "filename" : "icon_32@2x.png", "idiom" : "mac", "scale" : "2x", "size" : "32x32" },
    { "filename" : "icon_128.png", "idiom" : "mac", "scale" : "1x", "size" : "128x128" },
    { "filename" : "icon_128@2x.png", "idiom" : "mac", "scale" : "2x", "size" : "128x128" },
    { "filename" : "icon_256.png", "idiom" : "mac", "scale" : "1x", "size" : "256x256" },
    { "filename" : "icon_256@2x.png", "idiom" : "mac", "scale" : "2x", "size" : "256x256" },
    { "filename" : "icon_512.png", "idiom" : "mac", "scale" : "1x", "size" : "512x512" },
    { "filename" : "icon_512@2x.png", "idiom" : "mac", "scale" : "2x", "size" : "512x512" }
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}
"""
try! contents.write(toFile: "\(outDir)/Contents.json", atomically: true, encoding: .utf8)
print("wrote \(outDir)/Contents.json")
