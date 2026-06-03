//
//  LumitextSaverView.swift
//  LumitextSaver
//
//  The screensaver view. Hosts the shared SwiftUI renderer (LumitextCore.
//  LumitextTextView) via NSHostingView so the saver and the host app's live
//  preview draw identically. Reads the config once from the App Group container
//  at construction; the host app is the sole writer.
//
//  Per-screen instances are independent and hold no mutable shared state, so the
//  Tahoe multi-monitor pitfalls (which afflicted the leaky legacy host) don't apply
//  here — each appex instance runs in its own XPC process.
//

import ScreenSaver
import SwiftUI
import LumitextCore
import os.log

private let logger = Logger(subsystem: "io.github.fanhefeng.lumitext", category: "Saver")

final class LumitextSaverView: ScreenSaverView {

    private var hosting: NSHostingView<LumitextTextView>?

    override init?(frame: NSRect, isPreview: Bool) {
        super.init(frame: frame, isPreview: isPreview)
        wantsLayer = true
        setupHosting()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
        setupHosting()
    }

    deinit {
        // Explicit teardown so the hosted SwiftUI tree is released deterministically
        // rather than relying on ARC ordering (matches Aerial's pattern).
        hosting?.removeFromSuperview()
        hosting = nil
        logger.notice("deinit")
    }

    private func setupHosting() {
        let config = Self.loadConfig()
        let host = NSHostingView(rootView: LumitextTextView(config: config))
        host.frame = bounds
        host.autoresizingMask = [.width, .height]
        addSubview(host)
        hosting = host
        // Log only non-sensitive style metadata — never the user's text content.
        logger.notice("setupHosting family=\(config.fontFamily, privacy: .public) size=\(config.fontSize, privacy: .public)")
    }

    /// Load the user's config from the App Group container; fall back to defaults
    /// if the container or file is unavailable. Uses a bounded load so a slow/wedged
    /// container can never freeze the screensaver — it renders defaults instead.
    private static func loadConfig() -> LumitextConfig {
        guard let store = try? ConfigStore.appGroup() else {
            logger.error("App Group container unavailable; using default config")
            return .default
        }
        return store.load(timeout: 0.5)
    }

    // ScreenSaverView animation hooks are unused: SwiftUI self-drives any animation
    // and SSENeedsAnimationTimer=false, so we don't override animateOneFrame().
}
