//
//  SnapshotDumper.swift
//  Lumitext
//
//  Headless visual verification: when LUMITEXT_SNAPSHOT_OUT is set, the app launches
//  normally, lets the real window lay out, captures its AppKit contentView to a PNG,
//  and exits. Uses NSView.cacheDisplay (not ImageRenderer) so AppKit-backed controls
//  (ColorPicker, TextEditor, segmented pickers) render correctly. No screen-recording
//  permission required — we capture our own view tree.
//
//      LUMITEXT_SNAPSHOT_OUT=/tmp/app.png open -W /Applications/Lumitext.app
//

import AppKit

#if DEBUG
final class SnapshotAppDelegate: NSObject, NSApplicationDelegate {
    /// Debug-only diagnostics — but Debug builds are what gets shared as preview
    /// zips, so the env var must not be an arbitrary-path file-drop primitive:
    /// only paths under the user's home or the temp dirs are honored. The path
    /// is NORMALIZED first (`..` collapsed, symlinks resolved) — a prefix check
    /// on the raw string would be trivially bypassed by `/tmp/../etc/x`.
    static var outputPath: String? {
        guard let raw = ProcessInfo.processInfo.environment["LUMITEXT_SNAPSHOT_OUT"] else { return nil }
        let expanded = (raw as NSString).expandingTildeInPath
        // standardizingPath collapses "..", then resolve symlinks on the FULL
        // path — resolvingSymlinksInPath leaves nonexistent components as-is,
        // so a not-yet-created file is fine, while a pre-planted symlink AS the
        // final component can't redirect the write outside the allowlist.
        let standardized = (expanded as NSString).standardizingPath
        let resolved = URL(fileURLWithPath: standardized).resolvingSymlinksInPath().path
        let allowedRoots = [
            URL(fileURLWithPath: NSHomeDirectory()).resolvingSymlinksInPath().path + "/",
            URL(fileURLWithPath: NSTemporaryDirectory()).resolvingSymlinksInPath().path + "/",
            "/private/tmp/",
        ]
        guard !resolved.contains("/../"),
              allowedRoots.contains(where: { resolved.hasPrefix($0) }) else {
            FileHandle.standardError.write("SNAPSHOT refused path outside home/tmp: \(resolved)\n".data(using: .utf8)!)
            return nil
        }
        return resolved
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard let out = Self.outputPath else { return }
        // Stage 1: once the window exists, size it comfortably. Stage 2: after layout
        // settles, capture and quit. Splitting the resize from the capture lets
        // HSplitView re-lay-out (otherwise the left pane captures blank).
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            if let window = NSApp.windows.first(where: { $0.contentView != nil }) {
                window.setContentSize(NSSize(width: 1040, height: 720))
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                self.capture(to: out)
                exit(0)
            }
        }
    }

    private func capture(to path: String) {
        guard let window = NSApp.windows.first(where: { $0.contentView != nil && $0.isVisible })
                ?? NSApp.windows.first else {
            FileHandle.standardError.write("SNAPSHOT no window\n".data(using: .utf8)!)
            return
        }
        guard let view = window.contentView,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
            FileHandle.standardError.write("SNAPSHOT no contentView\n".data(using: .utf8)!)
            return
        }
        view.cacheDisplay(in: view.bounds, to: rep)
        guard let png = rep.representation(using: .png, properties: [:]) else {
            FileHandle.standardError.write("SNAPSHOT png encode failed\n".data(using: .utf8)!)
            return
        }
        do {
            try png.write(to: URL(fileURLWithPath: path))
            FileHandle.standardError.write("SNAPSHOT wrote \(path)\n".data(using: .utf8)!)
        } catch {
            FileHandle.standardError.write("SNAPSHOT write failed: \(error.localizedDescription)\n".data(using: .utf8)!)
        }
    }
}
#else
/// Release builds carry no snapshot hook (no env-triggered capture/exit paths);
/// the @NSApplicationDelegateAdaptor in LumitextApp still needs a delegate type.
final class SnapshotAppDelegate: NSObject, NSApplicationDelegate {}
#endif
