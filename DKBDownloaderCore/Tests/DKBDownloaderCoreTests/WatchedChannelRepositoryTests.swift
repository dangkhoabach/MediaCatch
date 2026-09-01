import Foundation
import GRDB
import Testing
@testable import DKBDownloaderCore

struct WatchedChannelRepositoryTests {
    private func makeRepo() throws -> WatchedChannelRepository {
        let db = try AppDatabase(inMemory: try DatabaseQueue())
        return WatchedChannelRepository(dbQueue: db.dbQueue)
    }

    @Test func insertsAndListsMostRecentFirst() throws {
        let repo = try makeRepo()
        let firstId = try repo.insert(url: "u1", title: "c1", outputDir: "/tmp", outputFormat: "mp4")
        let secondId = try repo.insert(url: "u2", title: "c2", outputDir: "/tmp", outputFormat: "mp4")

        let all = try repo.list()
        #expect(all.map(\.id) == [secondId, firstId])
        #expect(all.allSatisfy { $0.enabled && $0.intervalMinutes == 30 })
    }

    @Test func neverCheckedChannelIsDue() throws {
        let repo = try makeRepo()
        let id = try repo.insert(url: "u", title: "c", outputDir: "/tmp", outputFormat: "mp4")
        #expect(try repo.due().map(\.id) == [id])
    }

    @Test func recentlyCheckedChannelIsNotDue() throws {
        let repo = try makeRepo()
        let id = try repo.insert(url: "u", title: "c", outputDir: "/tmp", outputFormat: "mp4")
        try repo.touch(id: id)
        #expect(try repo.due().isEmpty)
    }

    @Test func disabledChannelIsNeverDue() throws {
        let repo = try makeRepo()
        let id = try repo.insert(url: "u", title: "c", outputDir: "/tmp", outputFormat: "mp4")
        try repo.setEnabled(id: id, enabled: false)
        #expect(try repo.due().isEmpty)
    }

    @Test func markVideoKnownIsIdempotentAndIsVideoKnownReflectsIt() throws {
        let repo = try makeRepo()
        let id = try repo.insert(url: "u", title: "c", outputDir: "/tmp", outputFormat: "mp4")

        #expect(try repo.isVideoKnown(channelId: id, videoId: "abc") == false)
        try repo.markVideoKnown(channelId: id, videoId: "abc")
        try repo.markVideoKnown(channelId: id, videoId: "abc") // must not throw on repeat
        #expect(try repo.isVideoKnown(channelId: id, videoId: "abc") == true)
        #expect(try repo.isVideoKnown(channelId: id, videoId: "other") == false)
    }

    @Test func removeDeletesChannelAndItsKnownVideos() throws {
        let repo = try makeRepo()
        let id = try repo.insert(url: "u", title: "c", outputDir: "/tmp", outputFormat: "mp4")
        try repo.markVideoKnown(channelId: id, videoId: "abc")

        try repo.remove(id: id)

        #expect(try repo.list().isEmpty)
        #expect(try repo.isVideoKnown(channelId: id, videoId: "abc") == false)
    }
}
