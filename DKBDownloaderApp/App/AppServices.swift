import DKBDownloaderCore
import Foundation

/// Composition root: resolves the real sidecar binary paths and wires up
/// every Core type that needs them, shared by Home (Phase 8) and
/// Queue/Library/Watch (Phase 9).
enum AppServices {
    static let ytdlpURL = resolvedBinaryURL(name: "yt-dlp")
    static let ffmpegURL = resolvedBinaryURL(name: "ffmpeg")

    static let ytdlpClient = YtdlpClient(ytdlpURL: ytdlpURL)
    static let ytdlpUpdater = YtdlpUpdater(ytdlpURL: ytdlpURL, binDirectory: AppDatabaseLocation.binDirectory())

    static let downloadRepo = DownloadRepository(dbQueue: AppDatabase.shared.dbQueue)
    static let urlHistoryRepo = UrlHistoryRepository(dbQueue: AppDatabase.shared.dbQueue)
    static let watchedChannelRepo = WatchedChannelRepository(dbQueue: AppDatabase.shared.dbQueue)

    static let downloadManager = DownloadManager(
        ytdlpURL: ytdlpURL, ffmpegURL: ffmpegURL, downloadRepo: downloadRepo,
        maxConcurrent: AppSettings.maxConcurrentDownloads()
    )

    static let channelWatcher = ChannelWatcher(
        playlistDumper: ytdlpClient, channelRepo: watchedChannelRepo, downloadStarter: downloadManager
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
