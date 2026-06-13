//
//  AppDirectoriesTests.swift
//  LumitextCoreTests
//
//  Locks in the dev/prod path split: production uses the shipped locations, and
//  development suffixes the per-user trees with `-Dev` and nests config under a
//  `dev/` subdirectory that STAYS inside the saver's sandbox exception. Also covers
//  FileLog's append + size-based rotation.
//

import XCTest
@testable import LumitextCore

final class AppDirectoriesTests: XCTestCase {

    func testSharedConfigProductionIsShippedPath() {
        XCTAssertEqual(AppDirectories.sharedConfig(.production).path, "/Users/Shared/Lumitext")
    }

    func testSharedConfigDevelopmentIsSubdirectoryOfProduction() {
        // Critical: the dev path must remain UNDER /Users/Shared/Lumitext/ so the
        // saver's read-only entitlement (scoped to that prefix) still covers it.
        let dev = AppDirectories.sharedConfig(.development).path
        XCTAssertEqual(dev, "/Users/Shared/Lumitext/dev")
        XCTAssertTrue(dev.hasPrefix("/Users/Shared/Lumitext/"),
                      "dev config must stay inside the saver's sandbox exception")
    }

    func testPerUserTreesSuffixOnlyInDevelopment() {
        for (env, suffix) in [(AppEnvironment.production, ""), (.development, "-Dev")] {
            XCTAssertTrue(AppDirectories.logs(env).path.hasSuffix("/Library/Logs/Lumitext\(suffix)"))
            XCTAssertTrue(AppDirectories.caches(env).path.hasSuffix("/Library/Caches/Lumitext\(suffix)"))
            XCTAssertTrue(AppDirectories.applicationSupport(env).path
                .hasSuffix("/Library/Application Support/Lumitext\(suffix)"))
        }
    }

    // MARK: - Trusted chain (squat defense for the dev subdirectory)

    func testTrustedChainProductionIsRootOnly() {
        let chain = ConfigStore.trustedChain(forLeaf: AppDirectories.sharedConfig(.production))
        XCTAssertEqual(chain.map(\.path), ["/Users/Shared/Lumitext"])
    }

    func testTrustedChainDevelopmentIncludesParent() {
        // The whole point of the fix: the dev leaf's parent (/Users/Shared/Lumitext)
        // must also be trust-checked, since unlike /Users/Shared it isn't sticky.
        let chain = ConfigStore.trustedChain(forLeaf: AppDirectories.sharedConfig(.development))
        XCTAssertEqual(chain.map(\.path), ["/Users/Shared/Lumitext", "/Users/Shared/Lumitext/dev"])
    }

    func testTrustedChainForeignLeafIsLeafOnly() {
        // An injected/custom dir (tests, /tmp) keeps the original leaf-only contract —
        // we never walk up to "/" verifying directories we don't own.
        let custom = URL(fileURLWithPath: "/tmp/some/injected/dir", isDirectory: true)
        XCTAssertEqual(ConfigStore.trustedChain(forLeaf: custom).map(\.path),
                       ["/tmp/some/injected/dir"])
    }

    func testEnsureDirectoryExistsCreatesAndTrustsChainInTempRoot() throws {
        // Drive ensureDirectoryExists against a temp tree (no /Users/Shared needed):
        // a foreign leaf is treated as leaf-only, so a nested store still creates and
        // trusts its own directory.
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("lumitext-chain-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ConfigStore(directory: root.appendingPathComponent("nested", isDirectory: true))
        try store.ensureDirectoryExists()
        var isDir: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: root.appendingPathComponent("nested").path, isDirectory: &isDir))
        XCTAssertTrue(isDir.boolValue)
    }

    func testEnsureCreatesDirectory() throws {
        let target = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("lumitext-test-\(UUID().uuidString)/nested", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: target.deletingLastPathComponent()) }
        XCTAssertFalse(FileManager.default.fileExists(atPath: target.path))
        try AppDirectories.ensure(target)
        var isDir: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: target.path, isDirectory: &isDir))
        XCTAssertTrue(isDir.boolValue)
    }

    // MARK: - FileLog

    private func makeTempDir() -> URL {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("lumitext-filelog-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func testFileLogInitDoesNoIO() {
        // init must not touch disk — the directory is created lazily at first write,
        // so the first log on a hot path (launch main thread) never blocks on I/O.
        let dir = makeTempDir().appendingPathComponent("not-yet", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir.deletingLastPathComponent()) }
        _ = FileLog(directory: dir, fileName: "t.log")
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.path),
                       "FileLog.init must not create its directory")
    }

    func testFileLogAppendsLines() throws {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let log = FileLog(directory: dir, fileName: "t.log")
        log.write(.error, category: "Test", "boom")
        log.write(.info, category: "Test", "hello")

        let contents = try waitForFileContents(at: dir.appendingPathComponent("t.log"))
        XCTAssertTrue(contents.contains("[error] [Test] boom"))
        XCTAssertTrue(contents.contains("[info] [Test] hello"))
    }

    func testFileLogRotatesPastMaxBytes() throws {
        let dir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        // Tiny cap so a couple of lines trip rotation.
        let log = FileLog(directory: dir, fileName: "t.log", maxBytes: 200)
        for i in 0..<50 { log.write(.notice, category: "Rotate", "line \(i) padding padding padding") }

        let rotated = dir.appendingPathComponent("t.log.1")
        _ = try waitForFileContents(at: rotated)   // rotation produced a backup
        XCTAssertTrue(FileManager.default.fileExists(atPath: rotated.path))
        // The active file was reopened and is below the cap (well under total written).
        let activeSize = (try FileManager.default
            .attributesOfItem(atPath: dir.appendingPathComponent("t.log").path)[.size] as? Int) ?? .max
        XCTAssertLessThan(activeSize, 50 * 40)
    }

    /// FileLog writes asynchronously on its private queue, so poll briefly for the
    /// expected file rather than asserting immediately.
    private func waitForFileContents(at url: URL, timeout: TimeInterval = 2) throws -> String {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let data = try? Data(contentsOf: url), !data.isEmpty {
                return String(decoding: data, as: UTF8.self)
            }
            Thread.sleep(forTimeInterval: 0.02)
        }
        XCTFail("file never appeared/filled at \(url.path)")
        return ""
    }
}
