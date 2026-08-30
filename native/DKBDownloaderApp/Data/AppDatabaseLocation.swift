import Foundation

/// Resolves to the exact same path the Tauri app already writes to —
/// `~/Library/Application Support/<bundle id>/dkb-downloader.db` — per D4:
/// this is an in-place upgrade that reads the existing database, not a
/// fresh one under a new identity. Copied from DKB Monitor's already-proven
/// `native/` code (Mục 1.5 in docs/swift-native-port-plan.md).
enum AppDatabaseLocation {
    static func productionPath() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let bundleID = Bundle.main.bundleIdentifier ?? "com.dangkhoabach.dkb-downloader"
        let dir = base.appendingPathComponent(bundleID, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("dkb-downloader.db")
    }
}
