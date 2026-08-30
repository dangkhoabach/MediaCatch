import DKBDownloaderCore
import Foundation

/// Minimal composition root: resolves the real sidecar binary paths and
/// wires up the Core types that need them. Kept intentionally small — just
/// what Home (Phase 8) needs to fetch/download for real. `ChannelWatcher`
/// (Watch, Phase 9) and notification-event wiring are added when those
/// phases need them, not preemptively here.
enum AppServices {
    static let ytdlpURL = resolvedBinaryURL(name: "yt-dlp")
    static let ffmpegURL = resolvedBinaryURL(name: "ffmpeg")

    static let ytdlpClient = YtdlpClient(ytdlpURL: ytdlpURL)

    static let downloadRepo = DownloadRepository(dbQueue: AppDatabase.shared!.dbQueue)
    static let urlHistoryRepo = UrlHistoryRepository(dbQueue: AppDatabase.shared!.dbQueue)

    static let downloadManager = DownloadManager(
        ytdlpURL: ytdlpURL, ffmpegURL: ffmpegURL, downloadRepo: downloadRepo
    )

    /// Prefers a copy previously fetched by `YtdlpUpdater` into
    /// `Application Support/<bundle id>/bin/` over the bundled sidecar seed
    /// binary in `Contents/Resources/bin/` — mirrors
    /// `ytdlp.rs::ytdlp_command`'s same preference order (D12).
    private static func resolvedBinaryURL(name: String) -> URL {
        let updated = AppDatabaseLocation.binDirectory().appendingPathComponent(name)
        if FileManager.default.fileExists(atPath: updated.path) {
            return updated
        }
        return Bundle.main.resourceURL!.appendingPathComponent("bin").appendingPathComponent(name)
    }
}
