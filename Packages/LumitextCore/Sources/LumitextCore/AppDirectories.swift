//
//  AppDirectories.swift
//  LumitextCore
//
//  One place that answers "where does Lumitext put its files?" — and gives a
//  DIFFERENT answer for Debug vs Release builds so iterating on a dev build never
//  reads or clobbers the real data a shipped install owns (and vice versa).
//
//  The environment is decided at COMPILE time (`#if DEBUG`). Both the host app and
//  the sandboxed saver appex depend on LumitextCore and are built together under the
//  same configuration, so they always agree on which set of directories to use
//  without any runtime handshake.
//
//  Per-user trees (logs, caches, application support) live under ~/Library and are
//  only ever written by the NON-sandboxed host. The saver appex is sandboxed to a
//  read-only exception on the shared config directory and cannot write here — its
//  diagnostics stay in the unified os.log (see AppLog).
//

import Foundation

/// Which file tree a build uses. Debug → a separate, suffixed set so a dev build's
/// config/logs/caches never mix with a shipped install's.
public enum AppEnvironment: Sendable {
    case production
    case development

    /// Resolved once at compile time. SPM dependencies are built with the host's
    /// configuration, so a Debug app + its embedded Debug saver both see `.development`.
    public static let current: AppEnvironment = {
        #if DEBUG
        return .development
        #else
        return .production
        #endif
    }()

    /// Suffix appended to the per-user folder name (`Lumitext` → `Lumitext-Dev`),
    /// so the two environments are visibly distinct in Finder.
    public var folderSuffix: String {
        switch self {
        case .production: return ""
        case .development: return "-Dev"
        }
    }
}

/// Environment-aware locations for everything Lumitext writes. Every accessor takes
/// an explicit `environment` (defaulting to `.current`) so the path logic is unit
/// testable without depending on the build configuration the tests happen to run in.
public enum AppDirectories {

    /// Base folder name; the environment suffix is appended for the per-user trees.
    private static let appName = "Lumitext"

    // MARK: Per-user trees (host-only; ~/Library/…)

    /// Rotating text logs written by the host's AppLog: `~/Library/Logs/Lumitext[-Dev]`.
    public static func logs(_ environment: AppEnvironment = .current) -> URL {
        userLibrary().appendingPathComponent("Logs", isDirectory: true)
            .appendingPathComponent(appName + environment.folderSuffix, isDirectory: true)
    }

    /// Discardable caches (regenerable data only): `~/Library/Caches/Lumitext[-Dev]`.
    public static func caches(_ environment: AppEnvironment = .current) -> URL {
        userLibrary().appendingPathComponent("Caches", isDirectory: true)
            .appendingPathComponent(appName + environment.folderSuffix, isDirectory: true)
    }

    /// Durable per-user app data: `~/Library/Application Support/Lumitext[-Dev]`.
    public static func applicationSupport(_ environment: AppEnvironment = .current) -> URL {
        userLibrary().appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent(appName + environment.folderSuffix, isDirectory: true)
    }

    // MARK: Cross-process config channel (host writes, saver reads)

    /// The directory holding `config.json`. Production lives at the shipped path
    /// `/Users/Shared/Lumitext`; development uses a `dev` SUBDIRECTORY of it
    /// (`/Users/Shared/Lumitext/dev`) rather than a sibling, so the single
    /// read-only sandbox exception the saver carries (`/Users/Shared/Lumitext/`)
    /// still covers it — a sibling like `…/Lumitext-Dev` would fall outside that
    /// prefix and the dev saver couldn't read its own config. Keep in sync with
    /// Saver/LumitextSaver*.entitlements.
    public static func sharedConfig(_ environment: AppEnvironment = .current) -> URL {
        let root = URL(fileURLWithPath: "/Users/Shared/Lumitext", isDirectory: true)
        switch environment {
        case .production: return root
        case .development: return root.appendingPathComponent("dev", isDirectory: true)
        }
    }

    // MARK: Helpers

    /// `~/Library` for the current user. The standard search-path API is preferred;
    /// the NSHomeDirectory fallback only fires if it somehow returns nothing (it
    /// doesn't for a real login session). Correct because the only consumer is the
    /// non-sandboxed host — a sandboxed process would get its container instead, but
    /// the saver never calls this.
    private static func userLibrary() -> URL {
        if let url = try? FileManager.default.url(
            for: .libraryDirectory, in: .userDomainMask, appropriateFor: nil, create: false) {
            return url
        }
        return URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
            .appendingPathComponent("Library", isDirectory: true)
    }

    /// Create `url` (and intermediates) if absent and return it, so callers can
    /// "open this folder" without first checking existence. Throws only if creation
    /// genuinely fails (permissions, a non-directory squatting the path).
    @discardableResult
    public static func ensure(_ url: URL) throws -> URL {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
