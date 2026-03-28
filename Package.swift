// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "brain-ios",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(name: "BrainCore", targets: ["BrainCore"]),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift", from: "7.0.0"),
        .package(url: "https://github.com/apple/swift-crypto", from: "3.0.0"),
    ],
    targets: [
        .target(
            name: "BrainCore",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift"),
                .product(name: "Crypto", package: "swift-crypto"),
            ],
            path: "Sources/BrainCore"
        ),
        .testTarget(
            name: "BrainCoreTests",
            dependencies: ["BrainCore"],
            path: "Tests/BrainCoreTests"
        ),
    ]
)
