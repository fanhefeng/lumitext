//
//  LumitextExtension.swift
//  LumitextSaver
//
//  Principal class for the screensaver extension. Specified as
//  NSExtensionPrincipalClass in Info.plist as
//  `$(PRODUCT_MODULE_NAME).LumitextExtension`.
//
//  Following Apple's own savers (e.g. Arabesque.appex) this stays minimal —
//  only init() is implemented; the framework drives the lifecycle.
//

import Foundation
import ScreenSaver
import os.log
import LumitextCore

private let logger = Logger(subsystem: Identifiers.subsystem, category: "Extension")

@objc(LumitextExtension)
class LumitextExtension: ScreenSaverExtension {

    @objc override init() {
        logger.notice("LumitextExtension.init() PID=\(ProcessInfo.processInfo.processIdentifier, privacy: .public)")
        super.init()
    }

    deinit {
        logger.notice("LumitextExtension.deinit")
    }
}
