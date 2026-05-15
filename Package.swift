// swift-tools-version: 6.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "better-monitor",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .executable(
            name: "better-monitor",
            targets: ["BetterMonitor"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.9.1"),
    ],
    targets: [
        .executableTarget(
            name: "BetterMonitor",
            dependencies: [
                "BetterMonitorC",
                .product(name: "Sparkle", package: "Sparkle"),
            ]
        ),
        .target(
            name: "BetterMonitorC"
        ),
        .testTarget(
            name: "BetterMonitorTests",
            dependencies: ["BetterMonitor"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
