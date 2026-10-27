import Foundation
import GRDB
import Testing
@testable import MediaCatchCore

/// The concurrency limit, exercised with stand-in executables so these need
/// neither the real yt-dlp binary nor a network.
struct DownloadManagerQueueTests {
    /// A fake "yt-dlp" that ignores the arguments it's handed. `sleep` keeps a
    /// slot occupied; `exit 0` frees it immediately.
    private func fakeExecutable(script: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("fake-ytdlp-\(UUID().uuidString)")
        try "#!/bin/sh\n\(script)\n".write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return url
    }

    private func makeRepo() throws -> DownloadRepository {
        DownloadRepository(dbQueue: try AppDatabase(inMemory: try DatabaseQueue()).dbQueue)
    }

    private func request(_ title: String) -> StartDownloadRequest {
        StartDownloadRequest(
            url: "https://example.com/\(title)", title: title, formatSelector: "best",
            outputDir: FileManager.default.temporaryDirectory.path, outputFormat: "mp4"
        )
    }

    @Test func holdsDownloadsBeyondTheLimitAsQueued() async throws {
        let repo = try makeRepo()
        let manager = DownloadManager(
            ytdlpURL: try fakeExecutable(script: "sleep 30"), ffmpegURL: nil, downloadRepo: repo, maxConcurrent: 2
        )

        let first = try await manager.start(request("one"))
        let second = try await manager.start(request("two"))
        let third = try await manager.start(request("three"))

        #expect(try repo.status(id: first) == .downloading)
        #expect(try repo.status(id: second) == .downloading)
        #expect(try repo.status(id: third) == .queued, "the third must wait for a slot")

        await manager.cancel(downloadId: third)
        await manager.terminateAll()
    }

    /// The row is inserted before the process is spawned, so a spawn that
    /// fails outright (the binary isn't there) used to leave it `.downloading`
    /// with nothing behind it — a permanent Queue entry until the next
    /// launch's reconcile relabelled it as "interrupted".
    @Test func aLaunchThatFailsMarksTheRowAsErrorInsteadOfLeavingItDownloading() async throws {
        let repo = try makeRepo()
        let missing = FileManager.default.temporaryDirectory.appendingPathComponent("no-such-ytdlp-\(UUID().uuidString)")
        let manager = DownloadManager(ytdlpURL: missing, ffmpegURL: nil, downloadRepo: repo, maxConcurrent: 2)

        await #expect(throws: (any Error).self) {
            try await manager.start(request("doomed"))
        }

        let rows = try repo.list()
        #expect(rows.count == 1)
        #expect(rows.first?.status == .error)
        #expect(rows.first?.errorMessage?.isEmpty == false)
    }

    @Test func cancellingAQueuedDownloadNeverStartsIt() async throws {
        let repo = try makeRepo()
        let manager = DownloadManager(
            ytdlpURL: try fakeExecutable(script: "sleep 30"), ffmpegURL: nil, downloadRepo: repo, maxConcurrent: 1
        )

        _ = try await manager.start(request("running"))
        let queued = try await manager.start(request("waiting"))
        #expect(try repo.status(id: queued) == .queued)

        await manager.cancel(downloadId: queued)
        #expect(try repo.status(id: queued) == .canceled)

        // Freeing the slot must not resurrect it.
        await manager.terminateAll()
        try await Task.sleep(for: .milliseconds(600))
        #expect(try repo.status(id: queued) == .canceled)
    }

    /// Every queued download has to eventually run: each finished one frees
    /// its slot and admits the next, until nothing is left waiting.
    @Test func drainsTheQueueAsSlotsFreeUp() async throws {
        let repo = try makeRepo()
        let manager = DownloadManager(
            ytdlpURL: try fakeExecutable(script: "exit 0"), ffmpegURL: nil, downloadRepo: repo, maxConcurrent: 1
        )

        for title in ["one", "two", "three"] {
            _ = try await manager.start(request(title))
        }

        var terminalEvents = 0
        for await event in manager.events {
            if case .progress = event { continue }
            terminalEvents += 1
            if terminalEvents == 3 { break }
        }

        let rows = try repo.list()
        #expect(rows.count == 3)
        #expect(
            rows.allSatisfy { $0.status != .queued && $0.status != .downloading },
            "nothing may be left waiting once every download has finished"
        )
    }

    @Test func raisingTheLimitAdmitsWaitingDownloadsImmediately() async throws {
        let repo = try makeRepo()
        let manager = DownloadManager(
            ytdlpURL: try fakeExecutable(script: "sleep 30"), ffmpegURL: nil, downloadRepo: repo, maxConcurrent: 1
        )

        _ = try await manager.start(request("running"))
        let waiting = try await manager.start(request("waiting"))
        #expect(try repo.status(id: waiting) == .queued)

        await manager.setMaxConcurrent(2)
        #expect(try repo.status(id: waiting) == .downloading)

        await manager.terminateAll()
    }
}
