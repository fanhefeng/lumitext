//
//  make-thumbnail.swift
//  Generates the System Settings thumbnail PNGs (107x65 @1x, 214x130 @2x)
//  for the saver appex. Works from any cwd:
//      swift scripts/make-thumbnail.swift
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

    let rect = NSRect(x: 0, y: 0, width: v.w, height: v.h)
    let gradient = NSGradient(
        starting: NSColor(calibratedRed: 0.13, green: 0.16, blue: 0.32, alpha: 1),
        ending: NSColor(calibratedRed: 0.03, green: 0.04, blue: 0.10, alpha: 1)
    )!
    gradient.draw(in: rect, angle: -90)

    let text = "Aa" as NSString
    let attrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: CGFloat(v.h) * 0.42, weight: .semibold),
        .foregroundColor: NSColor.white,
    ]
    let size = text.size(withAttributes: attrs)
    text.draw(
        at: NSPoint(x: (CGFloat(v.w) - size.width) / 2, y: (CGFloat(v.h) - size.height) / 2),
        withAttributes: attrs
    )

    NSGraphicsContext.restoreGraphicsState()

    guard let png = rep.representation(using: .png, properties: [:]) else {
        fatalError("could not encode png")
    }
    try! png.write(to: URL(fileURLWithPath: "\(outDir)/\(v.name)"))
    print("wrote \(outDir)/\(v.name) (\(v.w)x\(v.h))")
}
