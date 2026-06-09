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

private let logger = Logger(subsystem: Identifiers.subsystem, category: "Saver")

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
            let result = store.loadResult()
            DispatchQueue.main.async {
                // Bind first so the apply and its log line are atomic — an
                // optional-chained assignment would log "applied" even when the
                // view was torn down and the result silently dropped.
                guard let self, let hosting = self.hosting else {
                    logger.notice("view torn down before config apply; result discarded")
                    return
                }
                // The render policy (loaded → user config; missing → onboarding
                // default; failed → NOT the user's text, because a read problem
                // must not masquerade as lost text) is the tested
                // LoadResult.configToRender — this is just the thin apply shim.
                if let config = result.configToRender {
                    hosting.rootView = LumitextTextView(config: config)
                    // family is .private: a font choice is user data (the text
                    // itself is already deliberately never logged).
                    logger.notice("applied config path=\(store.path, privacy: .public) family=\(config.fontFamily, privacy: .private) size=\(config.fontSize, privacy: .public)")
                } else {
                    // A silent blank screen is undiagnosable for a non-technical
                    // user (the HOST reads the same file fine, so its preview
                    // looks correct and shows no warning). Render a small
                    // diagnostic hint instead of user-text — bilingual literal
                    // because the saver bundle ships no string tables.
                    hosting.rootView = LumitextTextView(config: Self.readFailureHint)
                    logger.error("config unreadable at \(store.path, privacy: .public); showing read-failure hint")
                }
            }
        }
    }

    /// Shown when the config exists but can't be read from the saver's sandbox
    /// (broken scoped exception, permissions drift). Deliberately small and
    /// diagnostic — it must read as a system note, never as the user's text.
    private static let readFailureHint: LumitextConfig = {
        var hint = LumitextConfig.default
        hint.text = "Lumitext couldn't read its settings — open the Lumitext app to fix this.\nLumitext 无法读取设置——请打开 Lumitext 应用检查。"
        hint.fontSize = 36
        hint.fontWeight = .regular
        hint.textColor = RGBAColor(red: 1, green: 1, blue: 1, alpha: 0.55)
        return hint
    }()

    // ScreenSaverView animation hooks are unused: SwiftUI self-drives any animation
    // and SSENeedsAnimationTimer=false, so we don't override animateOneFrame().
}
