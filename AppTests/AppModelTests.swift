//
//  AppModelTests.swift
//  LumitextAppTests
//
//  Hosted unit tests for AppModel's init decision table and persistence
//  bookkeeping — the logic earlier review rounds kept finding bugs in, now
//  testable via the overrideStore seam (a ConfigStore at a temp directory).
//

import XCTest
import LumitextCore
@testable import Lumitext

@MainActor
final class AppModelTests: XCTestCase {

    private func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("lumitext-apptests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func testLoadedConfigIsPresentedVerbatim() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = ConfigStore(directory: dir)
        var saved = LumitextConfig.default
        saved.text = "user's words"
        saved.fontSize = 64
        try store.saveWithRetry(saved)

        let model = AppModel(overrideStore: store)
        XCTAssertEqual(model.config, saved)
        XCTAssertNil(model.persistenceWarning)
    }

    /// Fresh install: localized onboarding text is presented AND persisted, so
    /// the WYSIWYG saver greets the user with the same words as the preview.
    func testFreshInstallShowsAndPersistsOnboardingText() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = ConfigStore(directory: dir)

        let model = AppModel(overrideStore: store)
        let expected = String(localized: "onboardingSampleText", defaultValue: "Hello, Lumitext")
        XCTAssertEqual(model.config.text, expected)

        // lastPersisted starts nil on a fresh install, so the synchronous
        // flush covers the eager write deterministically (no async waiting).
        model.flushPendingSave()
        XCTAssertEqual(try XCTUnwrap(store.loadResult().configToRender).text, expected)
    }

    /// The schemaVersion forward-compat gate, end to end on the host: a config
    /// from a NEWER build must surface a warning, show defaults, and NEVER be
    /// overwritten — not even by the quit-time flush after an edit.
    func testNewerSchemaConfigEntersReadOnlyMode() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let newer = #"{"text":"from the future","schemaVersion":\#(LumitextConfig.currentSchemaVersion + 1)}"#
        let fileURL = dir.appendingPathComponent(ConfigStore.fileName)
        try newer.data(using: .utf8)!.write(to: fileURL)

        let model = AppModel(overrideStore: ConfigStore(directory: dir))
        XCTAssertNotNil(model.persistenceWarning, "unreadable config must be surfaced")
        XCTAssertEqual(model.config, .default)

        model.config.text = "an edit that must not persist"
        model.flushPendingSave()
        let onDisk = try String(contentsOf: fileURL, encoding: .utf8)
        XCTAssertTrue(onDisk.contains("from the future"),
                      "the newer config must never be overwritten")
    }

    /// Out-of-order outcome reports: a stale (lower-seq) failure arriving after
    /// a newer success must be dropped, not surface a bogus warning.
    func testStaleOutcomeReportIsDropped() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = ConfigStore(directory: dir)
        try store.saveWithRetry(.default)
        let model = AppModel(overrideStore: store)

        model.applyOutcome(seq: 2, savedConfig: model.config, failure: nil)
        model.applyOutcome(seq: 1, savedConfig: model.config, failure: "stale boom")
        XCTAssertNil(model.persistenceWarning, "stale failure must not overwrite newer success")
    }

    /// A failed flush must NOT advance the persisted bookkeeping: once the
    /// directory becomes writable again, a retry flush must still write.
    func testFailedFlushRetriesAfterRecovery() throws {
        let parent = try makeTempDir()
        let dir = parent.appendingPathComponent("cfg")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: parent.path)
            try? FileManager.default.removeItem(at: parent)
        }
        let store = ConfigStore(directory: dir)
        try store.saveWithRetry(.default)
        let model = AppModel(overrideStore: store)

        // Break the world: remove the dir and make its parent unwritable so
        // even the recreate-retry fails.
        try FileManager.default.removeItem(at: dir)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: parent.path)
        model.config.text = "pending edit"
        model.flushPendingSave()   // fails; must NOT mark the edit persisted

        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: parent.path)
        model.flushPendingSave()   // recovery: must actually write now
        XCTAssertEqual(try XCTUnwrap(store.loadResult().configToRender).text, "pending edit")
    }
}
