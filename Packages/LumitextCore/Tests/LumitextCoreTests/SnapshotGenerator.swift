//
//  SnapshotGenerator.swift
//  LumitextCoreTests
//
//  Deterministic visual verification of the shared renderer without a screen,
//  the screensaver engine, or screen-recording permission. Uses SwiftUI's
//  ImageRenderer to rasterize LumitextTextView to PNGs.
//
//  Gated behind LUMITEXT_SNAPSHOT=1 so it doesn't run in normal `swift test`:
//      LUMITEXT_SNAPSHOT=1 LUMITEXT_SNAPSHOT_DIR=/tmp/lumitext-snaps \
//        swift test --filter SnapshotGenerator
//

import XCTest
import SwiftUI
@testable import LumitextCore

final class SnapshotGenerator: XCTestCase {

    @MainActor
    func testRenderSamples() throws {
        guard ProcessInfo.processInfo.environment["LUMITEXT_SNAPSHOT"] == "1" else {
            throw XCTSkip("set LUMITEXT_SNAPSHOT=1 to generate snapshots")
        }
        let outDir = URL(fileURLWithPath:
            ProcessInfo.processInfo.environment["LUMITEXT_SNAPSHOT_DIR"] ?? "/tmp/lumitext-snaps")
        try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

        let samples: [(String, LumitextConfig, CGSize)] = [
            ("default-fullhd", .default, CGSize(width: 1920, height: 1080)),
            // WYSIWYG miniature at 16:10 — the built-in-display aspect the live
            // preview defaults to (PreviewPane.mainScreenAspect's fallback),
            // so snapshot wrap points match what the preview predicts.
            ("default-preview", .default, CGSize(width: 480, height: 300)),
            ("custom", LumitextConfig(
                text: "晚安\nGood Night",
                fontFamily: "",
                fontWeight: .bold,
                fontSize: 160,
                textColor: RGBAColor(red: 1, green: 0.85, blue: 0.4),
                backgroundColor: RGBAColor(red: 0.05, green: 0.02, blue: 0.12),
                horizontalAlignment: .center,
                verticalAlignment: .center,
                lineSpacing: 10), CGSize(width: 1920, height: 1080)),
            ("top-leading", LumitextConfig(
                text: "Lumitext",
                fontWeight: .black,
                fontSize: 90,
                textColor: .white,
                backgroundColor: RGBAColor(red: 0.1, green: 0.1, blue: 0.12),
                horizontalAlignment: .leading,
                verticalAlignment: .top), CGSize(width: 1920, height: 1080)),
        ]

        for (name, config, size) in samples {
            let view = LumitextTextView(config: config).frame(width: size.width, height: size.height)
            let renderer = ImageRenderer(content: view)
            renderer.proposedSize = ProposedViewSize(size)
            guard let nsImage = renderer.nsImage,
                  let tiff = nsImage.tiffRepresentation,
                  let rep = NSBitmapImageRep(data: tiff),
                  let png = rep.representation(using: .png, properties: [:]) else {
                XCTFail("render failed for \(name)")
                continue
            }
            let url = outDir.appendingPathComponent("\(name).png")
            try png.write(to: url)
            print("SNAPSHOT \(url.path) \(Int(size.width))x\(Int(size.height))")
        }
    }
}
