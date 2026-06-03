//
//  LumitextSaverView.swift
//  LumitextSaver
//
//  M1 spike view: renders the results of the sandbox file-access probes
//  full-screen, so the config-channel decision (App Group vs /Users/Shared)
//  is verifiable both visually and via os.log.
//
//  This file will be replaced by the real text renderer (LumitextCore) in M3.
//

import ScreenSaver
import os.log

private let logger = Logger(subsystem: "io.github.fanhefeng.lumitext", category: "Saver")

final class LumitextSaverView: ScreenSaverView {

    static let appGroupID = "group.io.github.fanhefeng.lumitext"

    private var report: [String] = []

    override init?(frame: NSRect, isPreview: Bool) {
        super.init(frame: frame, isPreview: isPreview)
        wantsLayer = true
        report = Self.runProbes()
        for line in report {
            logger.info("PROBE \(line, privacy: .public)")
        }
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
    }

    deinit {
        logger.info("deinit")
    }

    // MARK: - Drawing

    override func draw(_ rect: NSRect) {
        NSColor(calibratedRed: 0.06, green: 0.08, blue: 0.16, alpha: 1).setFill()
        bounds.fill()

        let text = (["Lumitext M1 Spike — sandbox probes"] + report).joined(separator: "\n\n")
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: isPreview ? 5 : 20, weight: .medium),
            .foregroundColor: NSColor.white,
        ]
        (text as NSString).draw(
            in: bounds.insetBy(dx: bounds.width * 0.06, dy: bounds.height * 0.08),
            withAttributes: attrs
        )
    }

    // MARK: - Probes (M1 experiment)

    /// Each probe answers one architecture question:
    ///  1. Does the sandboxed appex resolve an App Group container?
    ///  2. Can it READ a file the (non-sandboxed) host wrote there?
    ///  3. Can it WRITE there (needed for future saver-side state)?
    ///  4. Is /Users/Shared readable (research says: NO without a
    ///     temporary-exception entitlement — captured here as evidence)?
    static func runProbes() -> [String] {
        var out: [String] = []
        out.append("home=\(NSHomeDirectory())")

        let fm = FileManager.default
        if let container = fm.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) {
            out.append("group.container=\(container.path)")

            let probe = container.appendingPathComponent("probe.txt")
            do {
                let s = try String(contentsOf: probe, encoding: .utf8)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                out.append("group.read=OK \"\(s)\"")
            } catch {
                out.append("group.read=FAIL \(error.localizedDescription)")
            }

            do {
                try "saver-write \(Date())".write(
                    to: container.appendingPathComponent("saver-write.txt"),
                    atomically: true,
                    encoding: .utf8
                )
                out.append("group.write=OK")
            } catch {
                out.append("group.write=FAIL \(error.localizedDescription)")
            }
        } else {
            out.append("group.container=NIL")
        }

        do {
            let s = try String(contentsOf: URL(fileURLWithPath: "/Users/Shared/Lumitext/probe.txt"), encoding: .utf8)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            out.append("shared.read=OK \"\(s)\"")
        } catch {
            out.append("shared.read=FAIL \(error.localizedDescription)")
        }

        return out
    }
}
