//
//  LumitextViewController.swift
//  LumitextSaver
//
//  Main view controller for the screensaver. Specified as
//  ScreenSaverViewControllerClass in Info.plist as
//  `$(PRODUCT_MODULE_NAME).LumitextViewController`.
//
//  Mirrors Apple's Arabesque.appex pattern: override the standard inits and
//  loadView(); let the framework drive everything else.
//

import AppKit
import ScreenSaver
import os.log
import LumitextCore

private let logger = Logger(subsystem: Identifiers.subsystem, category: "ViewController")

@objc(LumitextViewController)
class LumitextViewController: ScreenSaverViewController {

    /// Strong reference so the framework can't drop our view while we own it.
    private var saverView: LumitextSaverView?

    override init(nibName nibNameOrNil: NSNib.Name?, bundle nibBundleOrNil: Bundle?) {
        logger.notice("init(nibName:bundle:)")
        super.init(nibName: nibNameOrNil, bundle: nibBundleOrNil)
    }

    required init?(coder: NSCoder) {
        logger.notice("init(coder:)")
        super.init(coder: coder)
    }

    deinit {
        logger.notice("deinit")
    }

    override func loadView() {
        // The frame here is only an INITIAL size: the engine resizes the view to
        // the real display (or the small System Settings preview) after install,
        // and the hosted SwiftUI renderer reads its live GeometryReader size.
        // Because typography scales by container height (LumitextTextView), no
        // preview special-casing is needed, so we pass a constant isPreview —
        // the OS value is unreliable on Tahoe anyway (FB19201567). If
        // preview-specific behavior is ever needed, derive it from the laid-out
        // view width (< 400pt), NOT from NSScreen (the preview runs on a
        // full-size screen, so a screen-width test is always false).
        let frame = NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 1920, height: 1080)
        logger.notice("loadView() initialFrame=\(frame.width, privacy: .public)x\(frame.height, privacy: .public)")

        let view = LumitextSaverView(frame: frame, isPreview: false)
        if view == nil {
            logger.error("LumitextSaverView init returned nil; falling back to backdrop-only view")
        }
        saverView = view
        // Degraded fallback: still paint the product's default backdrop rather
        // than a bare (black) NSView, so an init failure reads as "saver with
        // no text" instead of a dead display.
        self.view = view ?? {
            let fallback = NSView(frame: frame)
            fallback.wantsLayer = true
            fallback.layer?.backgroundColor = LumitextConfig.default.backgroundColor.nsColor.cgColor
            return fallback
        }()
    }
}
