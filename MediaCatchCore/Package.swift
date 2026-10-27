// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MediaCatchCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "MediaCatchCore", targets: ["MediaCatchCore"])
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0")
    ],
    targets: [
        .target(name: "MediaCatchCore", dependencies: [.product(name: "GRDB", package: "GRDB.swift")]),
        .testTarget(name: "MediaCatchCoreTests", dependencies: ["MediaCatchCore"]),
    ]
)
