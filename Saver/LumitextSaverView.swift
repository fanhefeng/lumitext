//
//  LumitextSaverView.swift
//  LumitextSaver
//
//  The screensaver view. Hosts the shared SwiftUI renderer (LumitextCore.
//  LumitextTextView) via NSHostingView so the saver and the host app's live
//  preview draw identically. Reads the config from /Users/Shared/Lumitext at
//  construction (scoped read-only sandbox exception); the host is the sole writer.
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
        // Start with a TEXTLESS placeholder (just the default background) so the user
        // never sees wrong placeholder text, then load the real config off the main
        // thread and swap it in. Never blocks, never flashes "Hello, Lumitext".
        var placeholder = LumitextConfig.default
        placeholder.text = ""
        let host = NSHostingView(rootView: LumitextTextView(config: placeholder))
        host.frame = bounds
        host.autoresizingMask = [.width, .height]
        addSubview(host)
        hosting = host
        loadConfigAndApply()
    }

    /// Load the user's config from /Users/Shared/Lumitext off-thread (a plain file
    /// read via the scoped read-only sandbox exception — no containermanagerd vend,
    /// so it is fast), then apply on the main thread. Logs the path + style metadata
    /// so the read is verifiable from the unified log without exposing user text.
    private func loadConfigAndApply() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let store = ConfigStore.production()
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
