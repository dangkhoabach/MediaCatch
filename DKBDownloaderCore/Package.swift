// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DKBDownloaderCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "DKBDownloaderCore", targets: ["DKBDownloaderCore"])
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0")
    ],
    targets: [
        .target(name: "DKBDownloaderCore", dependencies: [.product(name: "GRDB", package: "GRDB.swift")]),
        .testTarget(name: "DKBDownloaderCoreTests", dependencies: ["DKBDownloaderCore"]),
    ]
)
