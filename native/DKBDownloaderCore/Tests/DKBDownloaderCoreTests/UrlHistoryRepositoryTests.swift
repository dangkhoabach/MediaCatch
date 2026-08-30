import GRDB
import Testing
@testable import DKBDownloaderCore

struct UrlHistoryRepositoryTests {
    private func makeRepo() throws -> UrlHistoryRepository {
        let db = try AppDatabase(inMemory: try DatabaseQueue())
        return UrlHistoryRepository(dbQueue: db.dbQueue)
    }

    @Test func firstUpsertInsertsWithFetchCountOne() throws {
        let repo = try makeRepo()
        try repo.upsert(url: "https://x.com/1", title: "Video 1")

        let all = try repo.list()
        #expect(all.count == 1)
        #expect(all[0].fetchCount == 1)
        #expect(all[0].title == "Video 1")
    }

    @Test func repeatUpsertBumpsFetchCountAndUpdatesTitle() throws {
        let repo = try makeRepo()
        try repo.upsert(url: "https://x.com/1", title: "Old Title")
        try repo.upsert(url: "https://x.com/1", title: "New Title")

        let all = try repo.list()
        #expect(all.count == 1, "same URL must not create a second row")
        #expect(all[0].fetchCount == 2)
        #expect(all[0].title == "New Title")
    }

    @Test func listOrdersByMostRecentlyFetchedFirst() throws {
        let repo = try makeRepo()
        try repo.upsert(url: "https://x.com/older", title: "older")
        try repo.upsert(url: "https://x.com/newer", title: "newer")
        // Re-fetch the older one so it becomes the most recent again.
        try repo.upsert(url: "https://x.com/older", title: "older")

        let urls = try repo.list().map(\.url)
        #expect(urls == ["https://x.com/older", "https://x.com/newer"])
    }

    @Test func deleteRemovesOnlyThatEntry() throws {
        let repo = try makeRepo()
        try repo.upsert(url: "https://x.com/1", title: "one")
        try repo.upsert(url: "https://x.com/2", title: "two")
        let idToDelete = try repo.list().first(where: { $0.url == "https://x.com/1" })!.id!

        try repo.delete(id: idToDelete)

        #expect(try repo.list().map(\.url) == ["https://x.com/2"])
    }

    @Test func clearRemovesEverything() throws {
        let repo = try makeRepo()
        try repo.upsert(url: "https://x.com/1", title: "one")
        try repo.upsert(url: "https://x.com/2", title: "two")

        try repo.clear()

        #expect(try repo.list().isEmpty)
    }
}
