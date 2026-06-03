//
//  ConfigStore.swift
//  LumitextCore
//
//  Reads/writes a single LumitextConfig as JSON in a directory. In production the
//  directory is the App Group container (host app = sole writer, saver = reader);
//  M1 verified the sandboxed appex resolves that container on Tahoe 26.5.
//
//  Deliberately uses EXACT-PATH file I/O only (never directory enumeration): the
//  saver's sandbox + Tahoe's container manager make `readdir` fragile, but
//  open()/read()/write() of a known path are reliable. Writes are atomic and
//  serialized so a half-written file is never observed by the reader.
//

import Foundation

public final class ConfigStore: @unchecked Sendable {

    public enum StoreError: Error {
        case appGroupContainerUnavailable
    }

    /// Production App Group identifier. Keep in sync with both targets' entitlements.
    public static let appGroupIdentifier = "group.io.github.fanhefeng.lumitext"

    /// File name inside the directory.
    public static let fileName = "config.json"

    private let fileURL: URL
    /// One process-wide serial queue shared by all ConfigStore instances, so two
    /// instances pointing at the same file can't interleave writes. (Cross-process
    /// safety still comes from the atomic write below — the saver and host are
    /// separate processes — but this removes the in-process footgun.)
    private static let ioQueue = DispatchQueue(label: "io.github.fanhefeng.lumitext.ConfigStore")
    private var ioQueue: DispatchQueue { ConfigStore.ioQueue }

    /// Create a store rooted at an explicit directory (used by tests with a temp dir,
    /// and by callers that already resolved the container URL).
    public init(directory: URL) {
        self.fileURL = directory.appendingPathComponent(ConfigStore.fileName)
    }

    /// Create a store rooted at the App Group container. Throws if the container
    /// can't be resolved (e.g. missing entitlement). Both the host app and the saver
    /// use this in production.
    public static func appGroup(
        identifier: String = ConfigStore.appGroupIdentifier
    ) throws -> ConfigStore {
        guard let url = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: identifier) else {
            throw StoreError.appGroupContainerUnavailable
        }
        return ConfigStore(directory: url)
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
}
