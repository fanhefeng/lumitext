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
        // Render defaults INSTANTLY (no blocking), then load the real config off the
        // main thread and swap it in. This never hangs the screen — even if the
        // sandboxed appex's first App Group container vend is slow on a cold start
        // (an aggressive synchronous timeout would wrongly fall back to default) —
        // and is always eventually correct.
        let host = NSHostingView(rootView: LumitextTextView(config: .default))
        host.frame = bounds
        host.autoresizingMask = [.width, .height]
        addSubview(host)
        hosting = host
        loadConfigAndApply()
    }

    /// Load the user's config from the App Group container off-thread, then apply it
    /// on the main thread. Logs the resolved path + applied size so the read path is
    /// verifiable from the unified log without exposing the user's text content.
    private func loadConfigAndApply() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let store = try? ConfigStore.appGroup() else {
                logger.error("App Group container unavailable; keeping default config")
                return
            }
            let config = store.load()
            DispatchQueue.main.async {
                self?.hosting?.rootView = LumitextTextView(config: config)
                logger.notice("applied config path=\(store.path, privacy: .public) family=\(config.fontFamily, privacy: .public) size=\(config.fontSize, privacy: .public)")
            }
        }
    }

    // ScreenSaverView animation hooks are unused: SwiftUI self-drives any animation
    // and SSENeedsAnimationTimer=false, so we don't override animateOneFrame().
}
