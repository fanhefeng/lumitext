import XCTest
@testable import LumitextCore

final class LumitextConfigTests: XCTestCase {

    private func encode(_ c: LumitextConfig) throws -> Data {
        try JSONEncoder().encode(c)
    }
    private func decode(_ data: Data) throws -> LumitextConfig {
        try JSONDecoder().decode(LumitextConfig.self, from: data)
    }

    func testDefaultRoundTrip() throws {
        let c = LumitextConfig.default
        XCTAssertEqual(try decode(encode(c)), c)
    }

    func testCustomRoundTrip() throws {
        let c = LumitextConfig(
            text: "多行\n文字 ✨",
            fontFamily: "Helvetica Neue",
            fontWeight: .bold,
            fontSize: 88,
            textColor: RGBAColor(red: 0.2, green: 0.4, blue: 0.9, alpha: 0.8),
            backgroundColor: .black,
            horizontalAlignment: .leading,
            verticalAlignment: .bottom,
            lineSpacing: 12
        )
        XCTAssertEqual(try decode(encode(c)), c)
    }

    func testColorRoundTrip() throws {
        let color = RGBAColor(red: 0.123, green: 0.456, blue: 0.789, alpha: 0.5)
        let data = try JSONEncoder().encode(color)
        XCTAssertEqual(try JSONDecoder().decode(RGBAColor.self, from: data), color)
    }

    /// Missing keys must fall back to defaults, not throw.
    func testDecodeMissingKeysFallsBackToDefaults() throws {
        let json = #"{"text":"only text"}"#.data(using: .utf8)!
        let c = try decode(json)
        XCTAssertEqual(c.text, "only text")
        XCTAssertEqual(c.fontSize, LumitextConfig.default.fontSize)
        XCTAssertEqual(c.fontWeight, LumitextConfig.default.fontWeight)
        XCTAssertEqual(c.backgroundColor, LumitextConfig.default.backgroundColor)
    }

    /// An unknown future enum value must fall back to the default for THAT field,
    /// leaving other fields intact (forward compatibility).
    func testDecodeUnknownEnumFallsBack() throws {
        let json = #"""
        {"text":"x","fontWeight":"ultralight","horizontalAlignment":"justified","fontSize":50}
        """#.data(using: .utf8)!
        let c = try decode(json)
        XCTAssertEqual(c.fontWeight, LumitextConfig.default.fontWeight)
        XCTAssertEqual(c.horizontalAlignment, LumitextConfig.default.horizontalAlignment)
        XCTAssertEqual(c.fontSize, 50) // unrelated field preserved
    }

    /// Unknown extra keys (from a newer schema) must be ignored, not throw.
    func testDecodeUnknownKeysIgnored() throws {
        let json = #"""
        {"text":"x","futureFeature":{"a":1},"gradientStops":[1,2,3]}
        """#.data(using: .utf8)!
        let c = try decode(json)
        XCTAssertEqual(c.text, "x")
    }

    func testEmptyDataIsNotDecodable() {
        XCTAssertThrowsError(try decode(Data()))
    }

    // MARK: - Numeric / color clamping (corrupt or hand-edited JSON must stay safe)

    /// Exact-equality, not ≥/≤: the spec is clamp-TO-EDGE. A regression that
    /// sent out-of-range values to the 120 fallback instead would still
    /// satisfy a ≥1/≤2000 inequality and ship green.
    func testZeroAndNegativeFontSizeClampedToLowerBound() throws {
        for raw in [0.0, -50.0] {
            let json = #"{"text":"x","fontSize":\#(raw)}"#.data(using: .utf8)!
            XCTAssertEqual(try decode(json).fontSize, LumitextConfig.fontSizeRange.lowerBound)
        }
    }

    func testAbsurdFontSizeClampedToUpperBound() throws {
        let json = #"{"text":"x","fontSize":999999}"#.data(using: .utf8)!
        XCTAssertEqual(try decode(json).fontSize, LumitextConfig.fontSizeRange.upperBound)
    }

    func testNegativeLineSpacingClampedToZero() throws {
        let json = #"{"text":"x","lineSpacing":-10}"#.data(using: .utf8)!
        XCTAssertEqual(try decode(json).lineSpacing, 0)
    }

    func testAbsurdLineSpacingClampedToUpperBound() throws {
        let json = #"{"text":"x","lineSpacing":5000}"#.data(using: .utf8)!
        XCTAssertEqual(try decode(json).lineSpacing, LumitextConfig.lineSpacingRange.upperBound)
    }

    /// fontSize/lineSpacing clamp on direct in-memory MUTATION (didSet), not just
    /// init/decode — so a programmatic assignment that bypasses the UI's clamps
    /// can't smuggle a NaN/out-of-range value into persistence or the renderer.
    func testFontSizeMutationClamps() {
        var c = LumitextConfig.default
        c.fontSize = 999_999
        XCTAssertEqual(c.fontSize, LumitextConfig.fontSizeRange.upperBound)
        c.fontSize = -5
        XCTAssertEqual(c.fontSize, LumitextConfig.fontSizeRange.lowerBound)
        c.fontSize = .nan
        XCTAssertEqual(c.fontSize, LumitextConfig.fallbackFontSize)
    }

    func testLineSpacingMutationClamps() {
        var c = LumitextConfig.default
        c.lineSpacing = 5000
        XCTAssertEqual(c.lineSpacing, LumitextConfig.lineSpacingRange.upperBound)
        c.lineSpacing = -10
        XCTAssertEqual(c.lineSpacing, 0)
        c.lineSpacing = .infinity
        XCTAssertEqual(c.lineSpacing, 0)
    }

    // MARK: - Opaque background (model-boundary contract)

    /// The saver engine draws black behind the view and the preview draws a
    /// window — a translucent background would render differently in each, so
    /// the model forces alpha = 1 on init AND decode.
    func testBackgroundAlphaForcedOpaqueOnInit() {
        let c = LumitextConfig(backgroundColor: RGBAColor(red: 0.1, green: 0.2, blue: 0.3, alpha: 0.4))
        XCTAssertEqual(c.backgroundColor.alpha, 1)
        XCTAssertEqual(c.backgroundColor.red, 0.1, accuracy: 0.0001)
    }

    func testBackgroundAlphaForcedOpaqueOnDecode() throws {
        let json = #"{"text":"x","backgroundColor":{"red":0.1,"green":0.2,"blue":0.3,"alpha":0.3}}"#.data(using: .utf8)!
        XCTAssertEqual(try decode(json).backgroundColor.alpha, 1)
    }

    /// …and on MUTATION: the host binds the picker/presets directly to the
    /// property, so the invariant must not depend on call-site discipline.
    func testBackgroundAlphaForcedOpaqueOnMutation() {
        var c = LumitextConfig.default
        c.backgroundColor = RGBAColor(red: 0.2, green: 0.3, blue: 0.4, alpha: 0.4)
        XCTAssertEqual(c.backgroundColor.alpha, 1)
        XCTAssertEqual(c.backgroundColor.red, 0.2, accuracy: 0.0001)
    }

    func testTextColorAlphaIsPreserved() throws {
        // Only the BACKGROUND is forced opaque — translucent text is a feature.
        let json = #"{"text":"x","textColor":{"red":1,"green":1,"blue":1,"alpha":0.5}}"#.data(using: .utf8)!
        XCTAssertEqual(try decode(json).textColor.alpha, 0.5)
    }

    func testOutOfRangeColorsClamped() throws {
        let json = #"{"text":"x","textColor":{"red":5,"green":-2,"blue":0.5,"alpha":9}}"#.data(using: .utf8)!
        let c = try decode(json).textColor
        XCTAssertEqual(c.red, 1)
        XCTAssertEqual(c.green, 0)
        XCTAssertEqual(c.blue, 0.5, accuracy: 0.0001)
        XCTAssertEqual(c.alpha, 1)
    }

    func testColorInitClampsDirectly() {
        let c = RGBAColor(red: 2, green: -1, blue: 0.3, alpha: 0.5)
        XCTAssertEqual(c.red, 1)
        XCTAssertEqual(c.green, 0)
        XCTAssertEqual(c.blue, 0.3, accuracy: 0.0001)
    }

    /// Channels clamp on MUTATION too (didSet) — direct in-memory assignment
    /// must not smuggle out-of-gamut or non-finite values past the boundary.
    func testColorChannelMutationClamps() {
        var c = RGBAColor.white
        c.red = 5
        c.green = -1
        c.blue = .nan
        c.alpha = .infinity
        XCTAssertEqual(c.red, 1)
        XCTAssertEqual(c.green, 0)
        XCTAssertEqual(c.blue, 0)
        XCTAssertEqual(c.alpha, 0)
    }

    // MARK: - Asymmetric missing-key color defaults (deliberate contract)
    //
    // A missing alpha decodes to 1 (opaque) while missing RGB channels decode
    // to 0. "Unifying" these to all-0 would make alpha 0 = fully transparent
    // text = invisible render — these tests pin the asymmetry.

    func testColorMissingAlphaDecodesOpaque() throws {
        let json = #"{"text":"x","textColor":{"red":0.2,"green":0.3,"blue":0.4}}"#.data(using: .utf8)!
        XCTAssertEqual(try decode(json).textColor.alpha, 1)
    }

    func testColorMissingChannelsDecodeToZero() throws {
        let json = #"{"text":"x","textColor":{"alpha":0.5}}"#.data(using: .utf8)!
        let c = try decode(json).textColor
        XCTAssertEqual(c.red, 0)
        XCTAssertEqual(c.green, 0)
        XCTAssertEqual(c.blue, 0)
        XCTAssertEqual(c.alpha, 0.5)
    }

    // MARK: - NaN / Infinity sanitization
    //
    // NaN can't arrive via JSON (invalid syntax → whole decode falls back to
    // .default), but the value inits are public API and must stay safe.

    /// EVERY non-finite value (NaN and ±infinity alike) collapses to the safe
    /// fallback — non-finites don't clamp to a range edge, they're discarded.
    /// Asserted against the SOURCE constants (not a literal) so the
    /// fallback-equals-default contract can't silently drift.
    func testNonFiniteFontSizeFallsBackToDefault() {
        XCTAssertEqual(LumitextConfig.default.fontSize, LumitextConfig.fallbackFontSize)
        for bad in [Double.nan, .infinity, -.infinity] {
            XCTAssertEqual(LumitextConfig(fontSize: bad).fontSize, LumitextConfig.fallbackFontSize)
        }
    }

    func testNonFiniteLineSpacingCollapsesToZero() {
        for bad in [Double.nan, .infinity, -.infinity] {
            XCTAssertEqual(LumitextConfig(lineSpacing: bad).lineSpacing, 0)
        }
    }

    func testNonFiniteColorChannelsCollapseToZero() {
        let c = RGBAColor(red: .nan, green: .infinity, blue: -.infinity, alpha: .nan)
        XCTAssertEqual(c.red, 0)
        XCTAssertEqual(c.green, 0)
        XCTAssertEqual(c.blue, 0)
        XCTAssertEqual(c.alpha, 0)
    }

    // MARK: - schemaVersion (the only future-migration gate)

    func testSchemaVersionRoundTripsAndIsPreservedOnDecode() throws {
        let json = #"{"text":"x","schemaVersion":99}"#.data(using: .utf8)!
        let c = try decode(json)
        XCTAssertEqual(c.schemaVersion, 99)
        XCTAssertEqual(try decode(encode(c)).schemaVersion, 99)
    }

    func testSchemaVersionDefaultsToCurrentWhenMissing() throws {
        let json = #"{"text":"x"}"#.data(using: .utf8)!
        XCTAssertEqual(try decode(json).schemaVersion, LumitextConfig.currentSchemaVersion)
    }

    // MARK: - Text length ceiling (same boundary-clamp philosophy as numerics)

    func testOversizedTextIsTruncatedOnInitAndDecode() throws {
        let huge = String(repeating: "字", count: LumitextConfig.maxTextLength + 500)
        XCTAssertEqual(LumitextConfig(text: huge).text.count, LumitextConfig.maxTextLength)
        let json = try JSONEncoder().encode(["text": huge])
        XCTAssertEqual(try decode(json).text.count, LumitextConfig.maxTextLength)
    }

    func testNormalTextIsNotTruncated() {
        XCTAssertEqual(LumitextConfig(text: "晚安").text, "晚安")
    }

    /// A single grapheme can hide many scalars (ZWJ emoji clusters) — the
    /// grapheme cap alone wouldn't bound decode/layout cost. Pinned on BOTH
    /// paths (init == decode), like the grapheme budget above.
    func testScalarHeavyTextIsBoundedByScalarBudget() throws {
        let cluster = "👨‍👩‍👧‍👦"   // 7 unicode scalars, 1 grapheme
        let heavy = String(repeating: cluster, count: LumitextConfig.maxTextLength)
        let clamped = LumitextConfig(text: heavy).text
        XCTAssertLessThanOrEqual(clamped.unicodeScalars.count, LumitextConfig.maxTextScalars)
        let json = try JSONEncoder().encode(["text": heavy])
        XCTAssertLessThanOrEqual(try decode(json).text.unicodeScalars.count,
                                 LumitextConfig.maxTextScalars)
    }

    /// SwiftUI lays out every line before clipping — line count is its own
    /// budget. Pinned on BOTH paths (init == decode).
    func testLineCountIsCapped() throws {
        let manyLines = String(repeating: "x\n", count: LumitextConfig.maxTextLines + 300)
        func lineCount(_ s: String) -> Int {
            s.split(separator: "\n", omittingEmptySubsequences: false).count
        }
        XCTAssertLessThanOrEqual(lineCount(LumitextConfig(text: manyLines).text),
                                 LumitextConfig.maxTextLines)
        let json = try JSONEncoder().encode(["text": manyLines])
        XCTAssertLessThanOrEqual(lineCount(try decode(json).text), LumitextConfig.maxTextLines)
    }

    func testFewLinesAreNotTouchedByLineCap() {
        XCTAssertEqual(LumitextConfig(text: "a\nb\nc").text, "a\nb\nc")
    }

    /// The scalar cut must land on a GRAPHEME boundary: when the budget falls
    /// mid-cluster, the torn cluster is dropped entirely (no invalid text)…
    func testScalarCutMidClusterKeepsOnlyWholeGraphemes() {
        // 7-scalar clusters; budget 8000 → 8000/7 = 1142 whole clusters + 6
        // scalars of a torn one, which must NOT survive.
        let cluster = "👨‍👩‍👧‍👦"
        let heavy = String(repeating: cluster, count: LumitextConfig.maxTextLength)
        let clamped = LumitextConfig(text: heavy).text
        let wholeClusters = LumitextConfig.maxTextScalars / cluster.unicodeScalars.count
        XCTAssertEqual(clamped.count, wholeClusters, "exactly the whole clusters that fit")
        XCTAssertEqual(clamped, String(repeating: cluster, count: wholeClusters),
                       "every surviving grapheme must be an intact cluster")
    }

    /// …and when the budget lands EXACTLY on a boundary, no intact grapheme is
    /// sacrificed (the old unconditional drop-last lost one here).
    func testScalarCutOnExactBoundaryKeepsEveryFittingGrapheme() {
        // 5-scalar grapheme: 'a' + 4 combining acute accents.
        let grapheme = "a\u{301}\u{301}\u{301}\u{301}"
        XCTAssertEqual(grapheme.unicodeScalars.count, 5)
        // 1600 graphemes × 5 = 8000 scalars: exactly the budget.
        let exact = String(repeating: grapheme, count: LumitextConfig.maxTextScalars / 5)
        XCTAssertEqual(LumitextConfig(text: exact).text, exact,
                       "a boundary-aligned cut must not drop the final grapheme")
        // One grapheme over: exactly one whole grapheme is shed, nothing torn.
        let over = exact + grapheme
        XCTAssertEqual(LumitextConfig(text: over).text, exact)
    }

    /// The GUI binds a TextEditor directly to `text`, so MUTATION must clamp
    /// too, not just init/decode — a giant paste must never reach the renderer
    /// (layout cost) or the on-disk config (file bloat). All three budgets.
    func testTextClampsOnMutation() {
        var c = LumitextConfig.default

        c.text = String(repeating: "字", count: LumitextConfig.maxTextLength + 500)
        XCTAssertEqual(c.text.count, LumitextConfig.maxTextLength)

        c.text = String(repeating: "👨‍👩‍👧‍👦", count: LumitextConfig.maxTextLength)
        XCTAssertLessThanOrEqual(c.text.unicodeScalars.count, LumitextConfig.maxTextScalars)

        c.text = String(repeating: "x\n", count: LumitextConfig.maxTextLines + 300)
        XCTAssertLessThanOrEqual(
            c.text.split(separator: "\n", omittingEmptySubsequences: false).count,
            LumitextConfig.maxTextLines)

        c.text = "normal"
        XCTAssertEqual(c.text, "normal", "in-budget text must pass through untouched")
    }

    // MARK: - Approximate color equality (preset-selection contract)

    /// ColorPicker round-trips drift below display precision; the UI's "is this
    /// preset applied?" check relies on isApproximately tolerating exactly that.
    func testIsApproximatelyToleratesSubDisplayPrecisionDrift() {
        let a = RGBAColor(red: 0.42, green: 0.42, blue: 0.42, alpha: 1)
        let drifted = RGBAColor(red: 0.42 + 0.002, green: 0.42 - 0.002, blue: 0.42, alpha: 1)
        XCTAssertTrue(a.isApproximately(drifted))
        XCTAssertNotEqual(a, drifted, "exact equality must still see the drift")
    }

    func testIsApproximatelyRejectsVisibleDifferences() {
        let a = RGBAColor(red: 0.42, green: 0.42, blue: 0.42, alpha: 1)
        XCTAssertFalse(a.isApproximately(RGBAColor(red: 0.43, green: 0.42, blue: 0.42, alpha: 1)))
        XCTAssertFalse(a.isApproximately(RGBAColor(red: 0.42, green: 0.42, blue: 0.42, alpha: 0.9)))
    }
}

// MARK: - Saver render policy (the appex's three-way decision, testable in CI)

final class RenderPolicyTests: XCTestCase {

    func testLoadedRendersTheUserConfig() {
        let config = LumitextConfig(text: "user's words")
        XCTAssertEqual(ConfigStore.LoadResult.loaded(config).configToRender, config)
    }

    func testMissingRendersOnboardingDefault() {
        XCTAssertEqual(ConfigStore.LoadResult.missing.configToRender, .default)
    }

    /// A read failure keeps the textless backdrop — it must NOT render the
    /// sample text and masquerade as the user's text being lost.
    func testFailedRendersNothing() {
        XCTAssertNil(ConfigStore.LoadResult.failed.configToRender)
    }
}

final class ConfigStoreTests: XCTestCase {

    private func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("lumitext-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func testSaveThenLoadRoundTrips() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = ConfigStore(directory: dir)

        var c = LumitextConfig.default
        c.text = "persisted"
        c.fontSize = 64
        try store.save(c)

        XCTAssertEqual(store.load(), c)
    }

    func testLoadMissingFileReturnsDefault() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        XCTAssertEqual(ConfigStore(directory: dir).load(), .default)
    }

    func testLoadCorruptFileReturnsDefault() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = ConfigStore(directory: dir)
        try "not json {{{".data(using: .utf8)!.write(to: dir.appendingPathComponent(ConfigStore.fileName))
        XCTAssertEqual(store.load(), .default)
    }

    func testOverwritePreservesLatest() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = ConfigStore(directory: dir)
        try store.save(LumitextConfig(text: "first"))
        try store.save(LumitextConfig(text: "second"))
        XCTAssertEqual(store.load().text, "second")
    }

    /// The host's save path relies on this throw to know it must recreate the
    /// shared directory and retry.
    func testSaveIntoMissingDirectoryThrows() throws {
        let dir = try makeTempDir()
        try FileManager.default.removeItem(at: dir)
        XCTAssertThrowsError(try ConfigStore(directory: dir).save(.default))
    }

    // MARK: - loadResult (the saver renders differently per outcome)

    func testLoadResultMissingFile() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        XCTAssertEqual(ConfigStore(directory: dir).loadResult(), .missing)
    }

    /// ENOENT discrimination must hold for a missing PARENT directory too —
    /// the freshest possible install, where /Users/Shared/Lumitext itself
    /// doesn't exist yet. .failed here would wrongly suppress onboarding.
    func testLoadResultMissingDirectoryIsMissing() throws {
        let dir = try makeTempDir()
        try FileManager.default.removeItem(at: dir)
        XCTAssertEqual(ConfigStore(directory: dir).loadResult(), .missing)
    }

    func testLoadResultCorruptFileIsFailed() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        try "not json {{{".data(using: .utf8)!.write(to: dir.appendingPathComponent(ConfigStore.fileName))
        XCTAssertEqual(ConfigStore(directory: dir).loadResult(), .failed)
    }

    func testLoadResultUnreadableFileIsFailed() throws {
        try XCTSkipIf(geteuid() == 0, "permission checks don't apply to root")
        let dir = try makeTempDir()
        let store = ConfigStore(directory: dir)
        try store.save(.default)
        // Make the directory untraversable to simulate a read denial (the unit
        // analogue of the saver's sandbox-exception misconfiguration).
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: dir.path)
        addTeardownBlock {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dir.path)
            try? FileManager.default.removeItem(at: dir)
        }
        XCTAssertEqual(store.loadResult(), .failed)
    }

    func testLoadResultLoaded() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = ConfigStore(directory: dir)
        var c = LumitextConfig.default
        c.text = "loaded"
        try store.save(c)
        XCTAssertEqual(store.loadResult(), .loaded(c))
    }

    /// A squatted multi-GB "config" must be refused BEFORE it is pulled into
    /// the saver process's memory — the model clamps bound the decode result,
    /// only this bound caps the read itself.
    func testLoadResultOversizedFileIsFailed() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let big = Data(count: ConfigStore.maxConfigFileBytes + 1)
        try big.write(to: dir.appendingPathComponent(ConfigStore.fileName))
        XCTAssertEqual(ConfigStore(directory: dir).loadResult(), .failed)
    }

    /// The missing-vs-failed classification is load-bearing (onboarding vs
    /// textless backdrop). One assertion per recognized code, so neither can
    /// silently fall out of the list.
    func testMissingFileErrorClassification() {
        for code in [NSFileReadNoSuchFileError, NSFileNoSuchFileError] {
            let err = NSError(domain: NSCocoaErrorDomain, code: code)
            XCTAssertTrue(ConfigStore.isMissingFileError(err), "code \(code) is ENOENT")
        }
        let denied = NSError(domain: NSCocoaErrorDomain, code: NSFileReadNoPermissionError)
        XCTAssertFalse(ConfigStore.isMissingFileError(denied), "EACCES is NOT missing")
        let posix = NSError(domain: NSPOSIXErrorDomain, code: Int(ENOENT))
        XCTAssertFalse(ConfigStore.isMissingFileError(posix), "non-Cocoa domain is not classified")
    }

    /// Forward-compat gate: a config claiming a NEWER schema than this build
    /// understands surfaces as .failed (saver keeps the textless backdrop,
    /// host shows defaults) — re-defined fields must never silently misrender.
    func testLoadResultNewerSchemaVersionIsFailed() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let json = #"{"text":"from the future","schemaVersion":\#(LumitextConfig.currentSchemaVersion + 1)}"#
        try json.data(using: .utf8)!.write(to: dir.appendingPathComponent(ConfigStore.fileName))
        XCTAssertEqual(ConfigStore(directory: dir).loadResult(), .failed)
    }

    /// Pins the write-retry primitive AppModel relies on: save into a vanished
    /// directory throws, the store can recreate ITS OWN directory, and the
    /// retried save then succeeds.
    func testEnsureDirectoryExistsEnablesRetryAfterVanishedDirectory() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = ConfigStore(directory: dir)
        try FileManager.default.removeItem(at: dir)

        XCTAssertThrowsError(try store.save(.default))
        try store.ensureDirectoryExists()
        XCTAssertNoThrow(try store.save(.default))
        XCTAssertEqual(store.load(), .default)
    }

    /// And the one-call wrapper the host actually uses: saveWithRetry recreates
    /// the vanished directory itself and lands the write.
    func testSaveWithRetryRecreatesVanishedDirectory() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = ConfigStore(directory: dir)
        try FileManager.default.removeItem(at: dir)

        XCTAssertNoThrow(try store.saveWithRetry(LumitextConfig(text: "retried")))
        XCTAssertEqual(store.load().text, "retried")
    }

    // MARK: - Directory trust (the /Users/Shared squat defense)
    //
    // Two of these XCTSkip under root (permission semantics don't apply to
    // uid 0). The suite is expected to run unprivileged — locally it always
    // does; if CI ever runs as root the skips show up in the test report
    // rather than passing vacuously.

    func testEnsureDirectoryCreatesOwnerOnlyWritable() throws {
        let parent = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: parent) }
        let dir = parent.appendingPathComponent("fresh")
        try ConfigStore(directory: dir).ensureDirectoryExists()

        let mode = try XCTUnwrap(
            FileManager.default.attributesOfItem(atPath: dir.path)[.posixPermissions] as? NSNumber
        )
        XCTAssertEqual(mode.uint16Value & 0o022, 0, "group/other write bits must be clear")
    }

    /// One test per WRITE BIT, not one 0o777 test: a 0o777 fixture trips on
    /// either bit, so dropping S_IWGRP (or S_IWOTH) from the mask would
    /// survive it. Isolating the bits kills both mutants.
    func testEnsureDirectoryRejectsGroupWritableDirectory() throws {
        try XCTSkipIf(geteuid() == 0, "permission checks don't apply to root")
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.setAttributes([.posixPermissions: 0o775], ofItemAtPath: dir.path)
        XCTAssertThrowsError(try ConfigStore(directory: dir).ensureDirectoryExists())
    }

    func testEnsureDirectoryRejectsOtherWritableDirectory() throws {
        try XCTSkipIf(geteuid() == 0, "permission checks don't apply to root")
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.setAttributes([.posixPermissions: 0o757], ofItemAtPath: dir.path)
        XCTAssertThrowsError(try ConfigStore(directory: dir).ensureDirectoryExists())
    }

    func testEnsureDirectoryRejectsSymlinkedDirectory() throws {
        let parent = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: parent) }
        let real = parent.appendingPathComponent("real")
        try FileManager.default.createDirectory(at: real, withIntermediateDirectories: true)
        let link = parent.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)

        XCTAssertThrowsError(try ConfigStore(directory: link).ensureDirectoryExists())
    }

    /// POSIX mode bits aren't the whole story: an extended ACL can grant
    /// "everyone add_file" on a 0755 directory. The host never creates ACLs,
    /// so any ACL entry must be treated as a squat.
    func testEnsureDirectoryRejectsACLBearingDirectory() throws {
        let dir = try makeTempDir()
        defer {
            // Strip the ACL before cleanup so removeItem can't be interfered with.
            let strip = Process()
            strip.executableURL = URL(fileURLWithPath: "/bin/chmod")
            strip.arguments = ["-N", dir.path]
            try? strip.run(); strip.waitUntilExit()
            try? FileManager.default.removeItem(at: dir)
        }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/chmod")
        p.arguments = ["+a", "everyone allow add_file,add_subdirectory", dir.path]
        try p.run(); p.waitUntilExit()
        try XCTSkipIf(p.terminationStatus != 0, "chmod +a unavailable in this environment")

        XCTAssertThrowsError(try ConfigStore(directory: dir).ensureDirectoryExists()) { error in
            guard case ConfigStoreError.untrustedDirectory = error else {
                return XCTFail("expected untrustedDirectory, got \(error)")
            }
        }
    }

    /// The foreign-owner branch (st_uid != getuid) is the core /Users/Shared
    /// squat defense but needs root to exercise (chown). Skipped unprivileged —
    /// visible in the test report rather than silently uncovered.
    func testEnsureDirectoryRejectsForeignOwnedDirectory() throws {
        try XCTSkipIf(geteuid() != 0, "chown to another uid requires root")
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        guard chown(dir.path, 1, numericCast(getgid())) == 0 else {
            return XCTFail("chown failed under root")
        }
        XCTAssertThrowsError(try ConfigStore(directory: dir).ensureDirectoryExists())
    }

    /// saveWithRetry must refuse an untrusted directory on the FAST path too —
    /// the directory can be swapped out from under a long-running host.
    func testSaveWithRetryRefusesUntrustedDirectory() throws {
        try XCTSkipIf(geteuid() == 0, "permission checks don't apply to root")
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.setAttributes([.posixPermissions: 0o777], ofItemAtPath: dir.path)
        XCTAssertThrowsError(try ConfigStore(directory: dir).saveWithRetry(.default))
    }
}

// MARK: - Save-outcome sequencing (the host's stale-report defense)

final class SaveOutcomeGateTests: XCTestCase {

    func testSequencesAreStrictlyIncreasing() {
        var gate = SaveOutcomeGate()
        XCTAssertEqual(gate.nextSequence(), 1)
        XCTAssertEqual(gate.nextSequence(), 2)
        XCTAssertEqual(gate.nextSequence(), 3)
    }

    func testInOrderOutcomesAreAdmitted() {
        var gate = SaveOutcomeGate()
        let first = gate.nextSequence()
        let second = gate.nextSequence()
        XCTAssertTrue(gate.admit(first))
        XCTAssertTrue(gate.admit(second))
    }

    /// The race this type exists for: write #1's outcome reaches the main
    /// actor AFTER write #2's. Admitting it would let an old failure (or stale
    /// success) overwrite the warning for the LATEST write.
    func testStaleOutcomeIsDropped() {
        var gate = SaveOutcomeGate()
        let first = gate.nextSequence()
        let second = gate.nextSequence()
        XCTAssertTrue(gate.admit(second))
        XCTAssertFalse(gate.admit(first), "older outcome arriving late must be dropped")
    }

    func testDuplicateOutcomeIsDropped() {
        var gate = SaveOutcomeGate()
        let seq = gate.nextSequence()
        XCTAssertTrue(gate.admit(seq))
        XCTAssertFalse(gate.admit(seq))
    }
}

// MARK: - WCAG contrast math (moved into Core from the app layer)

final class ColorContrastTests: XCTestCase {

    func testBlackOnWhiteIsMaxContrast() {
        XCTAssertEqual(contrastRatio(text: .black, background: .white), 21, accuracy: 0.01)
        XCTAssertEqual(contrastRatio(text: .white, background: .black), 21, accuracy: 0.01)
    }

    func testIdenticalColorsAreMinContrast() {
        XCTAssertEqual(contrastRatio(text: .white, background: .white), 1, accuracy: 0.001)
    }

    /// The compositing branch needs a DISCRIMINATING input. White-on-white α0.5
    /// composites to white (ratio 1) — but a naive alpha-ignoring implementation
    /// ALSO returns 1 for it, so that case alone can't falsify the compositing.
    /// Translucent BLACK on white can: composited it's mid-grey (≈3.98), while
    /// ignoring alpha scores it as opaque black-on-white (21). Deleting the
    /// compositing step must fail this test.
    func testTranslucentTextCompositesOverBackground() {
        let ghostWhite = RGBAColor(red: 1, green: 1, blue: 1, alpha: 0.5)
        XCTAssertEqual(contrastRatio(text: ghostWhite, background: .white), 1, accuracy: 0.001)

        let ghostBlack = RGBAColor(red: 0, green: 0, blue: 0, alpha: 0.5)
        XCTAssertEqual(contrastRatio(text: ghostBlack, background: .white), 3.98, accuracy: 0.05,
                       "0.5-alpha black over white must score as mid-grey, not opaque black (21)")
    }

    func testIsLight() {
        XCTAssertTrue(RGBAColor.white.isLight)
        XCTAssertFalse(RGBAColor.black.isLight)
        XCTAssertFalse(RGBAColor.defaultBackground.isLight)
    }

    /// Pin relativeLuminance itself to the WCAG-defined anchor values —
    /// contrastRatio alone could mask a luminance bug (a wrong luminance on
    /// BOTH sides can cancel out in the ratio).
    func testRelativeLuminanceKnownValues() {
        XCTAssertEqual(relativeLuminance(r: 1, g: 1, b: 1), 1, accuracy: 0.0001)
        XCTAssertEqual(relativeLuminance(r: 0, g: 0, b: 0), 0, accuracy: 0.0001)
        // Pure sRGB red: luminance equals the 0.2126 red coefficient.
        XCTAssertEqual(relativeLuminance(r: 1, g: 0, b: 0), 0.2126, accuracy: 0.0001)
        XCTAssertEqual(relativeLuminance(r: 0, g: 1, b: 0), 0.7152, accuracy: 0.0001)
        XCTAssertEqual(relativeLuminance(r: 0, g: 0, b: 1), 0.0722, accuracy: 0.0001)
    }
}
