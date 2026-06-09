//
//  ActivationLogicTests.swift
//  LumitextAppTests
//
//  Tests for ActivationManager's pure/parameterized logic: the /Applications
//  gate and the stage-and-swap move algorithm (driven entirely against temp
//  directories — every path is a parameter).
//

import XCTest
@testable import Lumitext

final class ActivationLogicTests: XCTestCase {

    // MARK: - /Applications gate

    func testApplicationsPathGate() {
        XCTAssertTrue(ActivationManager.isApplicationsPath("/Applications/Lumitext.app"))
        // Case-insensitive APFS can report non-canonical casing.
        XCTAssertTrue(ActivationManager.isApplicationsPath("/applications/Lumitext.app"))
        XCTAssertTrue(ActivationManager.isApplicationsPath("/APPLICATIONS/Lumitext.app"))
        // Anchored: per-user Applications and lookalike prefixes don't count.
        XCTAssertFalse(ActivationManager.isApplicationsPath("/Users/me/Applications/Lumitext.app"))
        XCTAssertFalse(ActivationManager.isApplicationsPath("/ApplicationsBackup/Lumitext.app"))
        XCTAssertFalse(ActivationManager.isApplicationsPath("/tmp/Applications/Lumitext.app"))
    }

    // MARK: - stageAndSwap (the move algorithm, on temp paths)

    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("lumitext-swaptests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    /// Build a minimal fake .app bundle. The executable name must match the
    /// running test host's (stageAndSwap derives it from Bundle.main).
    private func makeBundle(at url: URL, withExecutable: Bool) throws {
        let execName = Bundle.main.executableURL?.lastPathComponent ?? "Lumitext"
        let macOS = url.appendingPathComponent("Contents/MacOS")
        try FileManager.default.createDirectory(at: macOS, withIntermediateDirectories: true)
        if withExecutable {
            let exec = macOS.appendingPathComponent(execName)
            try "#!/bin/sh\n".data(using: .utf8)!.write(to: exec)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: exec.path)
        }
    }

    private func swapPaths() -> (source: String, dest: String, staging: String) {
        (root.appendingPathComponent("Source.app").path,
         root.appendingPathComponent("Dest.app").path,
         root.appendingPathComponent(".staging.app").path)
    }

    func testHappyPathLandsVerifiedCopyAndCleansUp() throws {
        let p = swapPaths()
        try makeBundle(at: URL(fileURLWithPath: p.source), withExecutable: true)

        XCTAssertNil(ActivationManager.stageAndSwap(source: p.source, dest: p.dest, staging: p.staging))
        XCTAssertTrue(FileManager.default.fileExists(atPath: p.dest))
        XCTAssertFalse(FileManager.default.fileExists(atPath: p.staging), "staging must be consumed")
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: root.path)
            .filter { $0.contains(".old-") }
        XCTAssertTrue(leftovers.isEmpty, "backup must be removed after a verified swap")
    }

    func testReplacingExistingInstallSucceeds() throws {
        let p = swapPaths()
        try makeBundle(at: URL(fileURLWithPath: p.source), withExecutable: true)
        try makeBundle(at: URL(fileURLWithPath: p.dest), withExecutable: true)

        XCTAssertNil(ActivationManager.stageAndSwap(source: p.source, dest: p.dest, staging: p.staging))
        XCTAssertTrue(FileManager.default.fileExists(atPath: p.dest))
    }

    /// The launchability guard: an incomplete copy must be rejected AND the
    /// previous install restored — never leave the dest empty.
    func testInvalidCopyRestoresPreviousInstall() throws {
        let p = swapPaths()
        try makeBundle(at: URL(fileURLWithPath: p.source), withExecutable: false)   // broken source
        try makeBundle(at: URL(fileURLWithPath: p.dest), withExecutable: true)      // working install
        let marker = URL(fileURLWithPath: p.dest).appendingPathComponent("Contents/marker")
        try "previous install".data(using: .utf8)!.write(to: marker)

        XCTAssertNotNil(ActivationManager.stageAndSwap(source: p.source, dest: p.dest, staging: p.staging),
                        "incomplete copy must be reported")
        XCTAssertTrue(FileManager.default.fileExists(atPath: p.dest), "previous install must be restored")
        XCTAssertEqual(try String(contentsOf: marker, encoding: .utf8), "previous install",
                       "the RESTORED bundle must be the original, not the broken copy")
    }
}
