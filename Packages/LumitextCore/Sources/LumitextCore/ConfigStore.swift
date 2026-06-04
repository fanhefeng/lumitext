//
//  ConfigStore.swift
//  LumitextCore
//
//  Reads/writes a single LumitextConfig as JSON in a directory. In production the
//  directory is /Users/Shared/Lumitext (host app = sole writer, saver = reader; the
//  sandboxed saver reads it via a scoped read-only temporary-exception entitlement —
//  the same shipped pattern Aerial v4 uses for /Users/Shared/Aerial).
//
//  Why not an App Group container: on macOS Tahoe, group containers are
//  TCC-protected and containermanagerd REJECTS access unless the group identifier is
//  prefixed with the requestor's Team ID — impossible for ad-hoc dev signing and an
//  avoidable trap even for shipped builds (live-diagnosed 2026-06-04, see ADR-0001).
//
//  Deliberately uses EXACT-PATH file I/O only (never directory enumeration), writes
//  are atomic and serialized so a half-written file is never observed by the reader.
//

import Foundation

// SAFETY (@unchecked Sendable): the only stored property, `fileURL`, is immutable
// after init; all file I/O is funneled through the shared static serial `ioQueue`;
// and writes are atomic (rename), so cross-process readers never see a torn file.
public final class ConfigStore: @unchecked Sendable {

    /// Production shared directory. World-readable by design (the saver reads it from
    /// its sandbox via a scoped temporary exception). Keep in sync with
    /// Saver/LumitextSaver*.entitlements.
    public static let sharedDirectory = URL(fileURLWithPath: "/Users/Shared/Lumitext", isDirectory: true)

    /// Legacy channel from the original App-Group design; only used to migrate an
    /// existing config the host wrote before the Tahoe TCC rejection was discovered.
    public static let legacyAppGroupIdentifier = "group.io.github.fanhefeng.lumitext"

    /// File name inside the directory.
    public static let fileName = "config.json"

    private let fileURL: URL
    /// One process-wide serial queue shared by all ConfigStore instances, so two
    /// instances pointing at the same file can't interleave writes. (Cross-process
    /// safety still comes from the atomic write below — the saver and host are
    /// separate processes — but this removes the in-process footgun.)
    private static let ioQueue = DispatchQueue(label: "io.github.fanhefeng.lumitext.ConfigStore")
    private var ioQueue: DispatchQueue { ConfigStore.ioQueue }

    /// Create a store rooted at an explicit directory (used by tests with a temp dir).
    public init(directory: URL) {
        self.fileURL = directory.appendingPathComponent(ConfigStore.fileName)
    }

    /// The production store at /Users/Shared/Lumitext. Never fails: the path is fixed.
    /// Writers should call `ensureDirectoryExists()` once before saving.
    public static func production() -> ConfigStore {
        ConfigStore(directory: sharedDirectory)
    }

    /// Create the shared directory if needed (host-side; the saver never writes).
    /// /Users/Shared is world-writable (mode 1777), so no privileges are required.
    public static func ensureDirectoryExists() throws {
        try FileManager.default.createDirectory(
            at: sharedDirectory,
            withIntermediateDirectories: true
        )
    }

    /// The absolute path being read/written (useful for diagnostics).
    public var path: String { fileURL.path }

    // MARK: - Read

    /// Load the config, or return `.default` if the file is missing or unreadable.
    /// Never throws: the saver must always have something to render.
    public func load() -> LumitextConfig {
        ioQueue.sync {
            guard let data = try? Data(contentsOf: fileURL) else { return .default }
            return (try? JSONDecoder().decode(LumitextConfig.self, from: data)) ?? .default
        }
    }

    /// Whether a config file exists at this store's path (used for migration).
    public var fileExists: Bool {
        FileManager.default.fileExists(atPath: fileURL.path)
    }

    // MARK: - Write

    /// Encode and write the config atomically. Serialized on a private queue so
    /// concurrent saves can't interleave.
    public func save(_ config: LumitextConfig) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(config)
        try ioQueue.sync {
            try data.write(to: fileURL, options: .atomic)
        }
    }

    // MARK: - Migration (host-side, one-time)

    /// If no config exists at the production path but one exists in the legacy
    /// App Group container (written by builds before the channel switch), copy it
    /// over so the user's settings survive. Host-only: the non-sandboxed host can
    /// still read the group container it wrote; the sandboxed saver cannot.
    public static func migrateLegacyConfigIfNeeded() {
        let store = production()
        guard !store.fileExists,
              let legacyDir = FileManager.default.containerURL(
                forSecurityApplicationGroupIdentifier: legacyAppGroupIdentifier) else { return }
        let legacy = ConfigStore(directory: legacyDir)
        guard legacy.fileExists else { return }
        let config = legacy.load()
        try? ensureDirectoryExists()
        try? store.save(config)
    }
}
