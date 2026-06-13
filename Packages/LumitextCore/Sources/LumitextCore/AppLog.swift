//
//  AppLog.swift
//  LumitextCore
//
//  The host's logging front door. Every call fans out to BOTH the unified os.log
//  (so the `log show --predicate 'subsystem == "…"'` workflow in CLAUDE.md keeps
//  working) and a rotating file in ~/Library/Logs (so there's an openable log to
//  hand a user — see the "Open Logs Folder" menu item).
//
//  Why a wrapper instead of os.Logger directly: os.Logger's privacy interpolation
//  (`\(x, privacy: .public)`) can't be forwarded to a file. Centralizing it here
//  lets call sites write plain `log.error("… \(x)")`; AppLog marks the whole
//  message `.public` for os.log (host diagnostics carry no user secrets — never the
//  config text) and writes the same string to the file.
//
//  Host-only by design. The sandboxed saver appex can't write to ~/Library, so it
//  keeps using os.Logger directly; its logs live solely in the unified log.
//

import Foundation
import os.log

public struct AppLog: Sendable {
    private let osLogger: os.Logger
    private let category: String

    public init(category: String) {
        self.osLogger = os.Logger(subsystem: Identifiers.subsystem, category: category)
        self.category = category
    }

    public func debug(_ message: @autoclosure () -> String) {
        let m = message()
        osLogger.debug("\(m, privacy: .public)")
        AppLogging.fileLog.write(.debug, category: category, m)
    }

    public func info(_ message: @autoclosure () -> String) {
        let m = message()
        osLogger.info("\(m, privacy: .public)")
        AppLogging.fileLog.write(.info, category: category, m)
    }

    public func notice(_ message: @autoclosure () -> String) {
        let m = message()
        osLogger.notice("\(m, privacy: .public)")
        AppLogging.fileLog.write(.notice, category: category, m)
    }

    public func error(_ message: @autoclosure () -> String) {
        let m = message()
        osLogger.error("\(m, privacy: .public)")
        AppLogging.fileLog.write(.error, category: category, m)
    }
}

/// Process-wide file-log sink. A `static let` is initialized at most once and is
/// thread-safe by Swift's runtime guarantee, so there's no bootstrap call to forget
/// and no race even if the first log comes from a background queue. Construction does
/// no I/O (FileLog defers directory/handle creation to its serial queue), so merely
/// touching this never blocks the caller; if the logs directory can't be created the
/// writes just no-op and os.log alone carries the diagnostics.
public enum AppLogging {
    public static let fileLog = FileLog(directory: AppDirectories.logs())
}
