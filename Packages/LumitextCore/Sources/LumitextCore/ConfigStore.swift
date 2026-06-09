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

    /// File name inside the directory.
    public static let fileName = "config.json"

    private let fileURL: URL
    /// One process-wide serial queue shared by all ConfigStore instances, so two
    /// instances pointing at the same file can't interleave writes. (Cross-process
    /// safety still comes from the atomic write below — the saver and host are
    /// separate processes — but this removes the in-process footgun.)
    private static let ioQueue = DispatchQueue(label: "\(Identifiers.subsystem).ConfigStore")

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
    /// Also throws `ConfigStoreError.untrustedDirectory` when the directory
    /// already exists but fails the trust check (foreign owner, other-writable,
    /// symlink) — see the instance overload below.
    public static func ensureDirectoryExists() throws {
        try production().ensureDirectoryExists()
    }

    /// Create THIS store's directory if needed — writers use it to recover when
    /// the directory vanished after launch (manual cleanup, disk tooling) — and
    /// REFUSE a directory we can't trust: /Users/Shared is world-writable (1777),
    /// so another local account could pre-create /Users/Shared/Lumitext and own
    /// it (classic /tmp-style squat); the sticky bit only protects entries you
    /// own from deletion, not from being created first. Once the directory is
    /// ours and not group/other-writable, the sticky parent prevents others from
    /// renaming or deleting it, so the post-check state is stable.
    public func ensureDirectoryExists() throws {
        let dir = fileURL.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: dir.path) {
            try FileManager.default.createDirectory(
                at: dir,
                withIntermediateDirectories: true,
                // Owner-writable only; world-readable + traversable so the
                // sandboxed saver can read config.json inside.
                attributes: [.posixPermissions: 0o755]
            )
        }
        try ConfigStore.verifyTrustedDirectory(dir)
    }

    /// A writer must only use a directory that is (a) a real directory, not a
    /// symlink someone planted, (b) owned by the current user, and (c) not
    /// writable by group/others.
    static func verifyTrustedDirectory(_ dir: URL) throws {
        var st = stat()
        guard lstat(dir.path, &st) == 0 else {
            throw ConfigStoreError.untrustedDirectory(dir.path, "cannot stat")
        }
        guard (st.st_mode & S_IFMT) == S_IFDIR else {
            throw ConfigStoreError.untrustedDirectory(dir.path, "not a real directory (symlink?)")
        }
        guard st.st_uid == getuid() else {
            throw ConfigStoreError.untrustedDirectory(dir.path, "owned by another user (uid \(st.st_uid))")
        }
        guard (st.st_mode & (S_IWGRP | S_IWOTH)) == 0 else {
            throw ConfigStoreError.untrustedDirectory(dir.path, "writable by other users")
        }
        // POSIX mode bits aren't the whole story on macOS: an extended ACL can
        // grant "everyone allow add_file" on a directory whose mode is still
        // 0755. The squat threat is specifically a WRITE grant to a principal we
        // don't control, so reject only ACLs that ALLOW a write-class permission
        // — not the mere presence of an ACL. A benign read-only ACL inherited
        // from a managed/MDM-administered /Users/Shared (the false-positive that
        // forced legitimate installs into in-memory mode) is left to pass; the
        // mode-bit and ownership checks above still bound the rest.
        if let acl = acl_get_file(dir.path, ACL_TYPE_EXTENDED) {
            defer { acl_free(UnsafeMutableRawPointer(acl)) }
            let writePerms: [acl_perm_t] = [
                ACL_WRITE_DATA, ACL_ADD_FILE, ACL_APPEND_DATA, ACL_ADD_SUBDIRECTORY,
                ACL_DELETE_CHILD, ACL_DELETE, ACL_WRITE_ATTRIBUTES,
                ACL_WRITE_EXTATTRIBUTES, ACL_WRITE_SECURITY, ACL_CHANGE_OWNER,
            ]
            var entry: acl_entry_t?
            var entryID = ACL_FIRST_ENTRY.rawValue
            while acl_get_entry(acl, entryID, &entry) == 0, let e = entry {
                entryID = ACL_NEXT_ENTRY.rawValue
                // Only ALLOW entries grant access; a DENY entry only removes it.
                var tag = acl_tag_t(ACL_UNDEFINED_TAG.rawValue)
                guard acl_get_tag_type(e, &tag) == 0,
                      tag == ACL_EXTENDED_ALLOW else { continue }
                var permset: acl_permset_t?
                guard acl_get_permset(e, &permset) == 0, let ps = permset else { continue }
                if writePerms.contains(where: { acl_get_perm_np(ps, $0) == 1 }) {
                    throw ConfigStoreError.untrustedDirectory(dir.path, "an access-control list grants write access")
                }
            }
        }
    }

    /// The absolute path being read/written (useful for diagnostics).
    public var path: String { fileURL.path }

    // MARK: - Read

    /// What a load attempt found, distinguishing "no config yet" (fresh install)
    /// from "config exists but can't be read/decoded" (sandbox denial, corruption).
    /// The saver renders differently for the two: a fresh install gets the default
    /// sample text; a read failure keeps a textless backdrop rather than claiming
    /// the user's text was lost.
    ///
    /// Read-path trust note: the HOST's reads are protected because AppModel.init
    /// calls ensureDirectoryExists() (which runs verifyTrustedDirectory) BEFORE
    /// the first load(). The SAVER deliberately does NOT verify ownership — the
    /// shared directory is legitimately owned by whichever user configured it,
    /// and the saver's exposure is bounded by the model's value clamps.
    public enum LoadResult: Equatable {
        case loaded(LumitextConfig)
        case missing
        case failed
    }

    /// A clamped config serializes to a few KB; anything beyond this ceiling is
    /// not a config — refuse to even read it. The model's text/number clamps
    /// bound the DECODED config, but only this bound caps the bytes a squatted
    /// file can force the saver process to pull into memory.
    public static let maxConfigFileBytes = 1_000_000

    /// "File doesn't exist" vs every other read failure — the saver renders
    /// onboarding for the former and a textless backdrop for the latter, so the
    /// classification is load-bearing. Extracted (and unit-tested) so neither
    /// ENOENT code can silently fall out of the list.
    static func isMissingFileError(_ error: Error) -> Bool {
        let ns = error as NSError
        // ENOENT surfaces as Cocoa 260 (read:no-such-file) or 4 (no-such-file);
        // anything else (EACCES from a broken sandbox exception, EIO, …) means
        // the file may well exist.
        return ns.domain == NSCocoaErrorDomain
            && [NSFileReadNoSuchFileError, NSFileNoSuchFileError].contains(ns.code)
    }

    /// Load with a detailed outcome. Never throws.
    public func loadResult() -> LoadResult {
        ConfigStore.ioQueue.sync {
            // Fast-fail on oversized files BEFORE reading…
            var st = stat()
            if lstat(fileURL.path, &st) == 0, st.st_size > ConfigStore.maxConfigFileBytes {
                return .failed
            }
            let data: Data
            do {
                // …mapped, not copied, so even a file swapped in AFTER the
                // lstat (path-based TOCTOU) can't force a giant heap read…
                data = try Data(contentsOf: fileURL, options: .mappedIfSafe)
            } catch {
                return ConfigStore.isMissingFileError(error) ? .missing : .failed
            }
            // …and the byte count is re-checked on the data actually mapped.
            guard data.count <= ConfigStore.maxConfigFileBytes else { return .failed }
            guard let config = try? JSONDecoder().decode(LumitextConfig.self, from: data) else {
                return .failed
            }
            // Forward-compat gate: a config written by a NEWER schema may have
            // re-defined field semantics; rendering it with this build's logic
            // could silently misrender the user's text. Treat it like a read
            // failure (saver keeps the textless backdrop, host shows defaults)
            // rather than guess. Additive changes don't bump the version, so
            // this only fires on a genuinely breaking future format.
            // Reject both newer-than-this-build AND pre-v1 (0/negative) versions:
            // a sub-1 version means a corrupt or hand-mangled file, never a real
            // Lumitext write, so treat it as a read failure rather than render it.
            guard (1...LumitextConfig.currentSchemaVersion).contains(config.schemaVersion) else {
                return .failed
            }
            return .loaded(config)
        }
    }

    /// Load the config, or return `.default` if the file is missing or unreadable.
    /// Never throws. `internal` — a TEST/simple-consumer convenience only:
    /// collapsing `.failed` to `.default` would violate the production contract
    /// (a read failure must NOT masquerade as the user's text), so production
    /// reads (host and saver) use `loadResult()`. Kept off the public API so no
    /// external caller can pick the lossy path by mistake.
    func load() -> LumitextConfig {
        switch loadResult() {
        case .loaded(let config): return config
        case .missing, .failed: return .default
        }
    }


    // MARK: - Write

    /// Encode and write the config atomically. Serialized on a private queue so
    /// concurrent saves can't interleave. Refuses an untrusted directory — the
    /// trust check guards EVERY write primitive, not just saveWithRetry, so no
    /// public path can be talked into writing inside a squatted directory.
    /// `internal`: `saveWithRetry` is the only write primitive external callers
    /// should use (it adds vanished-directory recovery); keeping `save` off the
    /// public surface prevents bypassing that retry contract.
    func save(_ config: LumitextConfig) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(config)
        let dir = fileURL.deletingLastPathComponent()
        // Verify trust and write in ONE critical section. If the check ran
        // outside the queue, the directory could be swapped between check and
        // write — the exact squat the trust check defends against. Serializing
        // both also keeps concurrent saves from interleaving.
        try ConfigStore.ioQueue.sync {
            try ConfigStore.verifyTrustedDirectory(dir)
            try data.write(to: fileURL, options: .atomic)
        }
    }

    /// Save once; if the directory vanished since launch (manual cleanup, disk
    /// tooling), recreate it and retry once before giving up. Directory trust
    /// is enforced by save() itself on every attempt — a long-running host's
    /// directory can be swapped out from under it, and an unverified write
    /// into a squatted directory must never succeed. This is the write
    /// primitive hosts should use for autosave: it lives in Core (not the app
    /// target) so both paths have direct unit coverage.
    public func saveWithRetry(_ config: LumitextConfig) throws {
        do {
            try save(config)
        } catch {
            // Vanished directory → recreate (which re-verifies) and retry.
            // A directory that EXISTS but fails the trust check rethrows here.
            try ensureDirectoryExists()
            try save(config)
        }
    }

}

public extension ConfigStore.LoadResult {
    /// The saver's render policy, extracted as a pure function so it is testable
    /// outside the appex sandbox: render the user's config when loaded, the
    /// default sample text on a fresh install, and NOTHING (nil → keep the
    /// textless backdrop) on a read failure — a read problem must not masquerade
    /// as the user's text being lost.
    var configToRender: LumitextConfig? {
        switch self {
        case .loaded(let config): return config
        case .missing: return .default
        case .failed: return nil
        }
    }
}

/// Errors a writer can hit when the shared channel can't be trusted; the host
/// surfaces `localizedDescription` in its persistence warning banner.
public enum ConfigStoreError: LocalizedError {
    case untrustedDirectory(String, String)

    public var errorDescription: String? {
        switch self {
        case .untrustedDirectory(let path, let reason):
            return "Refusing to use \(path): \(reason)."
        }
    }
}
