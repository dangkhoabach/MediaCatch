// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DKBDownloaderCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "DKBDownloaderCore", targets: ["DKBDownloaderCore"])
    ],
    targets: [
        .target(name: "DKBDownloaderCore"),
        .testTarget(name: "DKBDownloaderCoreTests", dependencies: ["DKBDownloaderCore"]),
    ]
)
