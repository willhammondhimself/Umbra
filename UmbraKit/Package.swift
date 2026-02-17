// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "UmbraKit",
    platforms: [
        .macOS(.v26),
        .iOS(.v26),
    ],
    products: [
        .library(name: "UmbraKit", targets: ["UmbraKit"]),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift", from: "7.4.1"),
    ],
    targets: [
        .target(
            name: "UmbraKit",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift"),
            ]
        ),
        .testTarget(
            name: "UmbraKitTests",
            dependencies: [
                "UmbraKit",
                .product(name: "GRDB", package: "GRDB.swift"),
            ]
        ),
    ]
)
