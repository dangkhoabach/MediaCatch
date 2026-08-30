import Foundation

public enum WatchEvent: Sendable, Equatable {
    case newVideoDownloading(channelTitle: String, videoTitle: String, downloadId: Int64)
}

/// Polls watched channels/playlists for new uploads — mirrors
/// `watch.rs::poll_due_channels` and the background loop that calls it in
/// `lib.rs::run`.
public actor ChannelWatcher {
    private let playlistDumper: any PlaylistDumping
    private let channelRepo: WatchedChannelRepository
    private let downloadStarter: any DownloadStarting
    private var loopTask: Task<Void, Never>?

    public nonisolated let events: AsyncStream<WatchEvent>
    private let eventsContinuation: AsyncStream<WatchEvent>.Continuation

    public init(playlistDumper: any PlaylistDumping, channelRepo: WatchedChannelRepository, downloadStarter: any DownloadStarting) {
        self.playlistDumper = playlistDumper
        self.channelRepo = channelRepo
        self.downloadStarter = downloadStarter
        var continuation: AsyncStream<WatchEvent>.Continuation!
        self.events = AsyncStream { continuation = $0 }
        self.eventsContinuation = continuation
    }

    /// Sleeps for `pollInterval` *after* each pass finishes, rather than on a
    /// fixed cadence — so there's no "missed tick" to catch up on: a machine
    /// that was asleep just resumes with a single poll on wake, not a burst.
    public func start(pollInterval: Duration = .seconds(300)) {
        guard loopTask == nil else { return }
        loopTask = Task { [weak self] in
            while let self, !Task.isCancelled {
                await self.tick()
                try? await Task.sleep(for: pollInterval)
            }
        }
    }

    public func stop() {
        loopTask?.cancel()
        loopTask = nil
    }

    /// One polling pass over every channel whose interval has elapsed —
    /// public so it can be called directly, independent of the loop (tests,
    /// and a future "check now" action).
    public func tick() async {
        for channel in (try? channelRepo.due()) ?? [] {
            await poll(channel)
        }
    }

    private func poll(_ channel: WatchedChannel) async {
        guard let channelId = channel.id else { return }
        guard let dump = try? await playlistDumper.dumpPlaylist(url: channel.url, limit: 5) else {
            return // transient network/extractor error — retry next tick
        }

        for entry in dump.entries.reversed() {
            // A DB read error is treated the same as "already known" (skip)
            // rather than risking a re-download — mirrors watch.rs's
            // `.unwrap_or(true)`.
            let alreadyKnown = (try? channelRepo.isVideoKnown(channelId: channelId, videoId: entry.id)) ?? true
            if alreadyKnown { continue }
            guard let videoURL = entry.url else { continue }
            let title = entry.title ?? entry.id

            try? channelRepo.markVideoKnown(channelId: channelId, videoId: entry.id)

            let request = StartDownloadRequest(
                url: videoURL, title: title, formatSelector: "bestvideo*+bestaudio/best",
                outputDir: channel.outputDir, outputFormat: channel.outputFormat
            )
            if let downloadId = try? await downloadStarter.start(request) {
                eventsContinuation.yield(.newVideoDownloading(channelTitle: channel.title, videoTitle: title, downloadId: downloadId))
            }
        }

        try? channelRepo.touch(id: channelId)
    }
}
