import Foundation
import GRDB
import Testing
@testable import DKBDownloaderCore

struct DownloadManagerIntegrationTests {
    @Test func fetchVideoInfoReturnsRealFormats() async throws {
        guard integrationTestsEnabled, let ytdlp = ytdlpBinaryURL() else { return }

        let client = YtdlpClient(ytdlpURL: ytdlp)
        let info = try await client.fetchVideoInfo(url: stableTestVideoURL)

        #expect(info.id == "jNQXAC9IVRw")
        #expect(!info.formats.isEmpty)
    }

    /// Full pipeline: start a real download through DownloadManager, drain
    /// its event stream to completion, and confirm both the moved file on
    /// disk and the DB record reflect a clean success — this is Phase 3's
    /// end-to-end exit criterion.
    @Test func downloadsARealVideoEndToEndAndUpdatesTheDatabase() async throws {
        guard integrationTestsEnabled, let ytdlp = ytdlpBinaryURL() else { return }

        let db = try AppDatabase(inMemory: try DatabaseQueue())
        let repo = DownloadRepository(dbQueue: db.dbQueue)
        let manager = DownloadManager(ytdlpURL: ytdlp, ffmpegURL: nil, downloadRepo: repo)

        let outputDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: outputDir) }

        let request = StartDownloadRequest(
            url: stableTestVideoURL, title: "Me at the zoo", formatSelector: "worstaudio",
            outputDir: outputDir.path, outputFormat: "mp4"
        )
        let downloadId = try await manager.start(request)

        var sawProgress = false
        var finalEvent: DownloadEvent?
        for await event in manager.events {
            if case .progress = event { sawProgress = true }
            if case .progress = event { continue }
            finalEvent = event
            break
        }

        guard case .completed(let eventDownloadId, let outputPath) = finalEvent else {
            Issue.record("expected a .completed event, got \(String(describing: finalEvent))")
            return
        }
        #expect(eventDownloadId == downloadId)
        #expect(sawProgress)
        #expect(FileManager.default.fileExists(atPath: outputPath))

        let record = try repo.list().first(where: { $0.id == downloadId })
        #expect(record?.status == .completed)
        #expect(record?.outputPath == outputPath)
    }
}
