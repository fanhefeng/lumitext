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

private let logger = Logger(subsystem: "io.github.fanhefeng.lumitext", category: "ViewController")

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
        // FB19201567: the OS-provided isPreview is unreliable on Tahoe.
        // Use the frame-width heuristic instead (System Settings previews are tiny).
        let frame = NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 1920, height: 1080)
        let isPreview = frame.width < 400
        logger.notice("loadView() frame=\(frame.width, privacy: .public)x\(frame.height, privacy: .public) isPreview=\(isPreview)")

        let view = LumitextSaverView(frame: frame, isPreview: isPreview)
        if view == nil {
            logger.error("LumitextSaverView init returned nil; falling back to blank NSView")
        }
        saverView = view
        self.view = view ?? NSView(frame: frame)
    }
}
