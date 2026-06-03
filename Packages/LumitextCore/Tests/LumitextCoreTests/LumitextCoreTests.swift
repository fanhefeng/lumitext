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

    func testZeroAndNegativeFontSizeClamped() throws {
        for raw in [0.0, -50.0] {
            let json = #"{"text":"x","fontSize":\#(raw)}"#.data(using: .utf8)!
            let c = try decode(json)
            XCTAssertGreaterThanOrEqual(c.fontSize, LumitextConfig.fontSizeRange.lowerBound)
        }
    }

    func testAbsurdFontSizeClamped() throws {
        let json = #"{"text":"x","fontSize":999999}"#.data(using: .utf8)!
        XCTAssertLessThanOrEqual(try decode(json).fontSize, LumitextConfig.fontSizeRange.upperBound)
    }

    func testNegativeLineSpacingClampedToZero() throws {
        let json = #"{"text":"x","lineSpacing":-10}"#.data(using: .utf8)!
        XCTAssertEqual(try decode(json).lineSpacing, 0)
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
}
