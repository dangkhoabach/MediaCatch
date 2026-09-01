import Foundation
import GRDB

public struct WatchedChannel: Codable, Identifiable, Equatable, Sendable {
    public var id: Int64?
    public var url: String
    public var title: String
    public var enabled: Bool
    public var intervalMinutes: Int
    public var outputDir: String
    public var outputFormat: String
    public var lastCheckedAt: Date?
    public var createdAt: Date

    public init(
        id: Int64? = nil,
        url: String,
        title: String,
        enabled: Bool = true,
        intervalMinutes: Int = 30,
        outputDir: String,
        outputFormat: String,
        lastCheckedAt: Date? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.url = url
        self.title = title
        self.enabled = enabled
        self.intervalMinutes = intervalMinutes
        self.outputDir = outputDir
        self.outputFormat = outputFormat
        self.lastCheckedAt = lastCheckedAt
        self.createdAt = createdAt
    }
}

extension WatchedChannel: FetchableRecord, MutablePersistableRecord {
    public static let databaseTableName = "watched_channels"

    enum CodingKeys: String, CodingKey {
        case id, url, title, enabled
        case intervalMinutes = "interval_minutes"
        case outputDir = "output_dir"
        case outputFormat = "output_format"
        case lastCheckedAt = "last_checked_at"
        case createdAt = "created_at"
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
