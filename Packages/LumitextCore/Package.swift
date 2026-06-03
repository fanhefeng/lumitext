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
    ]
)
