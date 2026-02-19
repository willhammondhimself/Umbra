// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "TetherKit",
    platforms: [
        .macOS(.v26),
        .iOS(.v26),
    ],
    products: [
        .library(name: "TetherKit", targets: ["TetherKit"]),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift", from: "7.4.1"),
        .package(url: "https://github.com/getsentry/sentry-cocoa", from: "8.40.0"),
        .package(url: "https://github.com/TelemetryDeck/SwiftSDK", from: "2.0.0"),
    ],
    targets: [
        .target(
            name: "TetherKit",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift"),
                .product(name: "Sentry", package: "sentry-cocoa"),
                .product(name: "TelemetryDeck", package: "SwiftSDK"),
            ]
        ),
        .testTarget(
            name: "TetherKitTests",
            dependencies: [
                "TetherKit",
                .product(name: "GRDB", package: "GRDB.swift"),
            ]
        ),
    ]
)
