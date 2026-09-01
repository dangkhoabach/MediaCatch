import GRDB
import Testing
@testable import DKBDownloaderCore

struct DownloadRepositoryTests {
    private func makeRepo() throws -> DownloadRepository {
        let db = try AppDatabase(inMemory: try DatabaseQueue())
        return DownloadRepository(dbQueue: db.dbQueue)
    }

    @Test func insertsAndListsMostRecentFirst() throws {
        let repo = try makeRepo()
        let firstId = try repo.insert(url: "u1", title: "first", formatSelector: "best", outputDir: "/tmp")
        let secondId = try repo.insert(url: "u2", title: "second", formatSelector: "best", outputDir: "/tmp")

        let all = try repo.list()
        #expect(all.map(\.id) == [secondId, firstId])
        #expect(all.allSatisfy { $0.status == .downloading })
    }

    @Test func setStatusAndOutputPath() throws {
        let repo = try makeRepo()
        let id = try repo.insert(url: "u", title: "t", formatSelector: "best", outputDir: "/tmp")

        try repo.setStatus(id: id, status: .completed)
        try repo.setOutputPath(id: id, outputPath: "/tmp/t.mp4")

        #expect(try repo.status(id: id) == .completed)
        #expect(try repo.outputPath(id: id) == "/tmp/t.mp4")
    }

    @Test func setStatusWithErrorMessage() throws {
        let repo = try makeRepo()
        let id = try repo.insert(url: "u", title: "t", formatSelector: "best", outputDir: "/tmp")

        try repo.setStatus(id: id, status: .error, errorMessage: "network unreachable")

        let record = try repo.list().first(where: { $0.id == id })
        #expect(record?.status == .error)
        #expect(record?.errorMessage == "network unreachable")
    }

    @Test func deleteRemovesTheRecord() throws {
        let repo = try makeRepo()
        let id = try repo.insert(url: "u", title: "t", formatSelector: "best", outputDir: "/tmp")
        try repo.delete(id: id)
        #expect(try repo.list().isEmpty)
    }
}
