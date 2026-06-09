// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LumitextCore",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(name: "LumitextCore", targets: ["LumitextCore"]),
    ],
    targets: [
        .target(
            name: "LumitextCore"
        ),
        .testTarget(
            name: "LumitextCoreTests",
            dependencies: ["LumitextCore"]
        ),
    ],
    // Explicit on purpose: the core builds in Swift 6 language mode (full strict
    // concurrency) under BOTH `swift test` and the Xcode project build, even
    // though the app targets compile at SWIFT_VERSION 5. Keeping the divergence
    // declared here means a future tools-version or default-mode change can't
    // silently flip the package's concurrency checking.
    swiftLanguageModes: [.v6]
)
