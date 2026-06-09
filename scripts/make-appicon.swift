//
//  make-appicon.swift
//  Generates the macOS AppIcon set: a night-indigo rounded-rect with a glowing
//  "Aa" — the product in one glyph. Works from any cwd:
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

    // Night-indigo vertical gradient.
    NSGradient(colors: [
        NSColor(srgbRed: 0.16, green: 0.18, blue: 0.38, alpha: 1),
        NSColor(srgbRed: 0.045, green: 0.055, blue: 0.14, alpha: 1),
    ])!.draw(in: shape, angle: -90)

    // Soft accent glow behind the glyph.
    let glow = NSGradient(colors: [
        NSColor(srgbRed: 0.39, green: 0.40, blue: 0.95, alpha: 0.55),
        NSColor(srgbRed: 0.39, green: 0.40, blue: 0.95, alpha: 0.0),
    ])!
    shape.addClip()
    glow.draw(fromCenter: NSPoint(x: s / 2, y: s * 0.46), radius: 0,
              toCenter: NSPoint(x: s / 2, y: s * 0.46), radius: s * 0.42,
              options: [])

    // The glyph.
    let text = "Aa" as NSString
    let font = NSFont.systemFont(ofSize: s * 0.34, weight: .bold)
    let shadow = NSShadow()
    shadow.shadowColor = NSColor(srgbRed: 0.5, green: 0.55, blue: 1.0, alpha: 0.8)
    shadow.shadowBlurRadius = s * 0.035
    let attrs: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: NSColor.white,
        .shadow: shadow,
    ]
    let size = text.size(withAttributes: attrs)
    text.draw(at: NSPoint(x: (s - size.width) / 2, y: (s - size.height) / 2), withAttributes: attrs)

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
