import Foundation

/// Resolves to the exact same path the Tauri app already writes to —
/// `~/Library/Application Support/<bundle id>/dkb-downloader.db`:
/// this is an in-place upgrade that reads the existing database, not a
/// fresh one under a new identity. Copied from DKB Monitor's already-proven
/// code.
enum AppDatabaseLocation {
    static func productionPath() -> URL {
        appDataDirectory().appendingPathComponent("dkb-downloader.db")
    }

    /// Where `YtdlpUpdater` writes a self-updated yt-dlp copy — mirrors
    /// `ytdlp.rs::ytdlp_command`'s `app_data_dir().join("bin")`, checked
    /// first (by `AppServices`) ahead of the bundled sidecar seed.
    static func binDirectory() -> URL {
        appDataDirectory().appendingPathComponent("bin", isDirectory: true)
    }

    private static func appDataDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let bundleID = Bundle.main.bundleIdentifier ?? "com.dangkhoabach.dkb-downloader"
        let dir = base.appendingPathComponent(bundleID, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}
