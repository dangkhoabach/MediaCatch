import Foundation
import GRDB
import Testing
@testable import MediaCatchCore

private struct FixedDump: PlaylistDumping {
    let dump: YtDlpPlaylistDump
    func dumpPlaylist(url: String, limit: Int?) async throws -> YtDlpPlaylistDump { dump }
}

private struct FailingDump: PlaylistDumping {
    func dumpPlaylist(url: String, limit: Int?) async throws -> YtDlpPlaylistDump {
        throw YtdlpError.processFailed("network unreachable")
    }
}

private actor RecordingDownloadStarter: DownloadStarting {
    private(set) var requests: [StartDownloadRequest] = []
    private var nextId: Int64 = 1

    func start(_ request: StartDownloadRequest) async throws -> Int64 {
        requests.append(request)
        defer { nextId += 1 }
        return nextId
    }
}

private func makeDump(entries: [(id: String, title: String?, url: String?)]) -> YtDlpPlaylistDump {
    let payload: [String: Any] = [
        "title": "channel",
        "entries": entries.map { entry -> [String: Any] in
            var dict: [String: Any] = ["id": entry.id, "url": entry.url as Any? ?? NSNull()]
            if let title = entry.title { dict["title"] = title }
            return dict
        },
    ]
    let data = try! JSONSerialization.data(withJSONObject: payload)
    return try! JSONDecoder().decode(YtDlpPlaylistDump.self, from: data)
}

struct ChannelWatcherTests {
    private func makeRepo() throws -> WatchedChannelRepository {
        let db = try AppDatabase(inMemory: try DatabaseQueue())
        return WatchedChannelRepository(dbQueue: db.dbQueue)
    }

    @Test func tickDownloadsOnlyVideosNotAlreadyKnown() async throws {
        let repo = try makeRepo()
        let channelId = try repo.insert(url: "https://x.com/channel", title: "My Channel", outputDir: "/tmp", outputFormat: "mp4")
        try repo.markVideoKnown(channelId: channelId, videoId: "old")

        let dump = makeDump(entries: [
            (id: "old", title: "Old video", url: "https://x.com/old"),
            (id: "new", title: "New video", url: "https://x.com/new"),
        ])
        let starter = RecordingDownloadStarter()
        let watcher = ChannelWatcher(playlistDumper: FixedDump(dump: dump), channelRepo: repo, downloadStarter: starter)

        await watcher.tick()

        let requests = await starter.requests
        #expect(requests.count == 1)
        #expect(requests[0].url == "https://x.com/new")
        #expect(requests[0].title == "New video")
        #expect(requests[0].formatSelector == "bestvideo*+bestaudio/best")
    }

    @Test func tickMarksNewVideosKnownSoASecondTickDoesNotRedownload() async throws {
        let repo = try makeRepo()
        let channelId = try repo.insert(url: "https://x.com/channel", title: "My Channel", outputDir: "/tmp", outputFormat: "mp4")
        let dump = makeDump(entries: [(id: "v1", title: "Video 1", url: "https://x.com/v1")])
        let starter = RecordingDownloadStarter()
        let watcher = ChannelWatcher(playlistDumper: FixedDump(dump: dump), channelRepo: repo, downloadStarter: starter)

        await watcher.tick()
        await watcher.tick()

        #expect(await starter.requests.count == 1)
        #expect(try repo.isVideoKnown(channelId: channelId, videoId: "v1"))
    }

    @Test func tickTouchesLastCheckedAtAfterPolling() async throws {
        let repo = try makeRepo()
        try repo.insert(url: "https://x.com/channel", title: "My Channel", outputDir: "/tmp", outputFormat: "mp4")
        let watcher = ChannelWatcher(
            playlistDumper: FixedDump(dump: makeDump(entries: [])), channelRepo: repo, downloadStarter: RecordingDownloadStarter()
        )

        #expect(try repo.due().count == 1, "never-checked channel starts out due")
        await watcher.tick()
        #expect(try repo.due().isEmpty, "touch() after polling should clear it from due until the interval elapses again")
    }

    @Test func tickSkipsDisabledChannels() async throws {
        let repo = try makeRepo()
        let channelId = try repo.insert(url: "https://x.com/channel", title: "My Channel", outputDir: "/tmp", outputFormat: "mp4")
        try repo.setEnabled(id: channelId, enabled: false)
        let starter = RecordingDownloadStarter()
        let watcher = ChannelWatcher(
            playlistDumper: FixedDump(dump: makeDump(entries: [(id: "v1", title: "v", url: "https://x.com/v1")])),
            channelRepo: repo, downloadStarter: starter
        )

        await watcher.tick()

        #expect(await starter.requests.isEmpty)
    }

    @Test func tickLeavesChannelDueAgainWhenPlaylistDumpFails() async throws {
        let repo = try makeRepo()
        try repo.insert(url: "https://x.com/channel", title: "My Channel", outputDir: "/tmp", outputFormat: "mp4")
        let watcher = ChannelWatcher(playlistDumper: FailingDump(), channelRepo: repo, downloadStarter: RecordingDownloadStarter())

        await watcher.tick()

        #expect(try repo.due().count == 1, "a transient dump failure must not mark the channel as checked")
    }

    @Test func skipsEntriesWithoutAUrl() async throws {
        let repo = try makeRepo()
        try repo.insert(url: "https://x.com/channel", title: "My Channel", outputDir: "/tmp", outputFormat: "mp4")
        let dump = makeDump(entries: [(id: "v1", title: "no url", url: nil)])
        let starter = RecordingDownloadStarter()
        let watcher = ChannelWatcher(playlistDumper: FixedDump(dump: dump), channelRepo: repo, downloadStarter: starter)

        await watcher.tick()

        #expect(await starter.requests.isEmpty)
    }
}
