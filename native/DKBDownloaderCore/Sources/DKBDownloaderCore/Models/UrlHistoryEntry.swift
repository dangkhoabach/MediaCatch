import Foundation
import GRDB

public struct UrlHistoryEntry: Codable, Identifiable, Equatable, Sendable {
    public var id: Int64?
    public var url: String
    public var title: String
    public var fetchCount: Int
    public var lastFetchedAt: Date

    public init(id: Int64? = nil, url: String, title: String, fetchCount: Int = 1, lastFetchedAt: Date = Date()) {
        self.id = id
        self.url = url
        self.title = title
        self.fetchCount = fetchCount
        self.lastFetchedAt = lastFetchedAt
    }
}

extension UrlHistoryEntry: FetchableRecord, MutablePersistableRecord {
    public static let databaseTableName = "url_history"

    enum CodingKeys: String, CodingKey {
        case id, url, title
        case fetchCount = "fetch_count"
        case lastFetchedAt = "last_fetched_at"
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
