//
//  FileLog.swift
//  LumitextCore
//
//  A small append-only text log with size-based rotation, used by the host so its
//  diagnostics land in a file the user can open (~/Library/Logs/Lumitext[-Dev]) —
//  the unified os.log is great for `log show` but isn't something you hand a
//  non-developer. AppLog tees every host log line into both.
//
//  Deliberately minimal: one active file plus a single `.1` backup, capped at a few
//  MB, so an always-on app can't grow an unbounded log. Logging must never crash or
//  block the app: every failure is swallowed, and ALL work — including the directory
//  creation and opening the file handle — happens on one private serial queue. `init`
//  itself touches no disk, so the first `log.*` call on a hot path (e.g. launch on the
//  main thread) never blocks on filesystem I/O; it just enqueues.
//

import Foundation

public final class FileLog: @unchecked Sendable {
    // SAFETY (@unchecked Sendable): `directory`, `fileURL`, `maxBytes`, `queue` are
    // immutable after init; the mutable `handle` / `didPrepareDirectory` and the
    // non-Sendable `formatter` are touched ONLY inside blocks dispatched on the
    // private serial `queue`, so there is no concurrent access. `Date` captured at the
    // call site is Sendable.

    public enum Level: String, Sendable {
        case debug, info, notice, error
    }

    private let directory: URL
    private let fileURL: URL
    private let maxBytes: Int
    private let queue: DispatchQueue
    private let formatter: ISO8601DateFormatter
    private var handle: FileHandle?
    private var didPrepareDirectory = false

    /// Configure a rotating log at `directory/fileName`. Does NO filesystem I/O — the
    /// directory and file are created lazily on the serial queue at the first write.
    public init(directory: URL, fileName: String = "lumitext.log", maxBytes: Int = 2_000_000) {
        self.directory = directory
        self.fileURL = directory.appendingPathComponent(fileName)
        self.maxBytes = maxBytes
        self.queue = DispatchQueue(label: "\(Identifiers.subsystem).FileLog")
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        self.formatter = fmt
    }

    /// Absolute path of the active log file (for diagnostics / "reveal in Finder").
    public var path: String { fileURL.path }

    /// Enqueue one line. Returns immediately — the timestamp is captured here so the
    /// recorded time is the log-call time, not when the queue drains.
    public func write(_ level: Level, category: String, _ message: String) {
        let date = Date()
        queue.async { [weak self] in
            self?.append(date: date, level: level, category: category, message: message)
        }
    }

    // MARK: - Serial-queue-confined I/O

    private func append(date: Date, level: Level, category: String, message: String) {
        let line = "\(formatter.string(from: date)) [\(level.rawValue)] [\(category)] \(message)\n"
        guard let data = line.data(using: .utf8) else { return }
        if handle == nil { openHandle() }
        rotateIfNeeded()
        guard let handle else { return }
        do {
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
        } catch {
            // seek/write failed: do NOT keep writing through this handle. A
            // swallowed seekToEnd() leaves the offset wherever it was, so a
            // follow-up write would land at the CURRENT position — overwriting
            // existing log bytes or scribbling mid-file. Drop this line and drop
            // the handle; the next append() sees handle == nil and openHandle()s
            // a fresh one positioned correctly. We're on the serial queue, so this
            // self.handle = nil is race-free, and swallowing keeps the "logging
            // never crashes / never blocks" contract intact.
            try? handle.close()
            self.handle = nil
        }
    }

    private func openHandle() {
        let fm = FileManager.default
        if !didPrepareDirectory {
            try? fm.createDirectory(at: directory, withIntermediateDirectories: true)
            // Only stop retrying once the directory actually exists — a transient
            // failure (disk full, perms) must not permanently disable file logging;
            // the next write should try to create it again.
            didPrepareDirectory = fm.fileExists(atPath: directory.path)
        }
        if !fm.fileExists(atPath: fileURL.path) {
            fm.createFile(atPath: fileURL.path, contents: nil)
        }
        handle = try? FileHandle(forWritingTo: fileURL)
    }

    /// When the active file reaches the cap, slide it to `<name>.1` (discarding any
    /// previous backup) and reopen a fresh empty file. If the slide-aside fails (the
    /// backup is locked, perms changed), TRUNCATE the active file instead of leaving
    /// it oversized: otherwise every subsequent write would re-trigger rotation, retry
    /// the failing move, and the log would grow without bound — the opposite of the
    /// cap this method exists to enforce. Truncating loses history but keeps the size
    /// bounded.
    private func rotateIfNeeded() {
        let attrs = try? FileManager.default.attributesOfItem(atPath: fileURL.path)
        let size = (attrs?[.size] as? NSNumber)?.intValue ?? 0
        guard size >= maxBytes else { return }
        try? handle?.close()
        handle = nil
        let rotated = fileURL.appendingPathExtension("1")
        try? FileManager.default.removeItem(at: rotated)
        do {
            try FileManager.default.moveItem(at: fileURL, to: rotated)
        } catch {
            if let h = try? FileHandle(forWritingTo: fileURL) {
                try? h.truncate(atOffset: 0)
                try? h.close()
            }
        }
        openHandle()
    }
}
