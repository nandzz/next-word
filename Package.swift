// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "NextWord",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "NextWord", targets: ["NextWord"])
    ],
    targets: [
        .executableTarget(
            name: "NextWord",
            path: "Sources/NextWord",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "NextWordTests",
            dependencies: ["NextWord"],
            path: "Tests/NextWordTests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
