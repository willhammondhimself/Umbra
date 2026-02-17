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
    ],
    targets: [
        .target(
            name: "TetherKit",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift"),
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
