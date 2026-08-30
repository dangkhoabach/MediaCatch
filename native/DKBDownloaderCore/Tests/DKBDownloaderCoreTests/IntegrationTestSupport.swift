import Foundation

/// Real-binary, real-network tests are gated behind an env var so a normal
/// `swift test` run (CI, or a dev machine without network) never depends on
/// network access or the sidecar binaries being present — set
/// RUN_YTDLP_INTEGRATION_TESTS=1 to exercise them.
func ytdlpBinaryURL() -> URL? {
    #if arch(arm64)
    let name = "yt-dlp-aarch64-apple-darwin"
    #else
    let name = "yt-dlp-x86_64-apple-darwin"
    #endif
    // <file>.swift -> DKBDownloaderCoreTests/ -> Tests/ -> DKBDownloaderCore/ -> native/ -> repo root
    let thisFile = URL(fileURLWithPath: #filePath)
    let repoRoot = thisFile
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let url = repoRoot.appendingPathComponent("src-tauri/binaries/\(name)")
    return FileManager.default.fileExists(atPath: url.path) ? url : nil
}

var integrationTestsEnabled: Bool {
    ProcessInfo.processInfo.environment["RUN_YTDLP_INTEGRATION_TESTS"] == "1"
}

/// A permanently-public, tiny YouTube video ("Me at the zoo", the first
/// video ever uploaded) used across integration tests instead of an
/// arbitrary/removable one.
let stableTestVideoURL = "https://www.youtube.com/watch?v=jNQXAC9IVRw"
