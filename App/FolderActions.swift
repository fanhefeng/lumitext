//
//  FolderActions.swift
//  Lumitext
//
//  Backs the "Open Folder ▸ …" menu items: reveal one of Lumitext's directories in
//  Finder, creating it first so the menu works even before anything has been written
//  there (a fresh install has no logs/cache yet). All paths are environment-aware
//  (Debug vs Release point at different folders) — see LumitextCore.AppDirectories.
//

import AppKit
import LumitextCore

enum FolderActions {
    /// Which directory a menu item opens. The cases ARE the menu, so localization
    /// and the open action both iterate this one list.
    enum Target: CaseIterable {
        case configuration, logs, cache, applicationSupport

        var url: URL {
            switch self {
            case .configuration:     return ConfigStore.sharedDirectory
            case .logs:              return AppDirectories.logs()
            case .cache:             return AppDirectories.caches()
            case .applicationSupport: return AppDirectories.applicationSupport()
            }
        }

        /// Menu label. Default values are the development-language (en) strings;
        /// zh-Hans overrides live in Localizable.strings.
        var label: String {
            switch self {
            case .configuration:
                return String(localized: "menuOpenConfig", defaultValue: "Configuration")
            case .logs:
                return String(localized: "menuOpenLogs", defaultValue: "Logs")
            case .cache:
                return String(localized: "menuOpenCache", defaultValue: "Cache")
            case .applicationSupport:
                return String(localized: "menuOpenAppSupport", defaultValue: "Application Support")
            }
        }
    }

    /// Create the directory if absent, then open it in Finder. Best-effort: a failed
    /// create still attempts the open (the folder may already exist), and a failed
    /// open is a no-op — nothing here should ever surface an error to the user.
    @MainActor
    static func open(_ target: Target) {
        switch target {
        case .configuration:
            // The shared config dir lives under world-writable /Users/Shared, so it
            // must be created with hardened permissions and trust-checked. Route
            // through the ONE Core creator rather than a bare createDirectory here —
            // a second creator with default (umask-dependent) perms could plant a
            // group/world-writable dir that ConfigStore's trust check then rejects,
            // silently degrading persistence to in-memory. If the create is refused
            // (already untrusted), we still try to reveal whatever is there.
            try? ConfigStore.ensureDirectoryExists()
        case .logs, .cache, .applicationSupport:
            // Per-user ~/Library trees: not world-writable, so a plain create is safe.
            try? AppDirectories.ensure(target.url)
        }
        NSWorkspace.shared.open(target.url)
    }
}
