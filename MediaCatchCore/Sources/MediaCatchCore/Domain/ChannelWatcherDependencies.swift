import Foundation

/// Abstracts the 2 pieces of `ChannelWatcher` that need real I/O (a real
/// yt-dlp process, a real download) — mirrors the same reasoning as DKB
/// Monitor's `SchedulerDependencies.swift`: it lets the watch-polling logic
/// itself (skip known videos, mark new ones, touch last-checked) be tested
/// headlessly with fakes, without spawning any process.
public protocol PlaylistDumping: Sendable {
    func dumpPlaylist(url: String, limit: Int?) async throws -> YtDlpPlaylistDump
}

public protocol DownloadStarting: Sendable {
    func start(_ request: StartDownloadRequest) async throws -> Int64
}

extension YtdlpClient: PlaylistDumping {}
extension DownloadManager: DownloadStarting {}
