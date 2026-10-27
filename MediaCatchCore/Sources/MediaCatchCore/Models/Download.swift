import Foundation
import GRDB

public enum DownloadStatus: String, Codable, Sendable {
    /// Accepted but waiting for a slot — `DownloadManager` only runs
    /// `maxConcurrent` downloads at a time. Stored as plain text like every
    /// other status, so adding it needed no schema change; rows written by
    /// older versions simply never carry it.
    case queued
    case downloading
    case completed
    case error
    case canceled
}

public struct Download: Codable, Identifiable, Equatable, Sendable {
    public var id: Int64?
    public var url: String
    public var title: String
    public var formatSelector: String
    public var outputDir: String
    public var outputPath: String?
    public var status: DownloadStatus
    public var errorMessage: String?
    public var createdAt: Date

    public init(
        id: Int64? = nil,
        url: String,
        title: String,
        formatSelector: String,
        outputDir: String,
        outputPath: String? = nil,
        status: DownloadStatus = .downloading,
        errorMessage: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.url = url
        self.title = title
        self.formatSelector = formatSelector
        self.outputDir = outputDir
        self.outputPath = outputPath
        self.status = status
        self.errorMessage = errorMessage
        self.createdAt = createdAt
    }
}

extension Download: FetchableRecord, MutablePersistableRecord {
    public static let databaseTableName = "downloads"

    enum CodingKeys: String, CodingKey {
        case id, url, title
        case formatSelector = "format_selector"
        case outputDir = "output_dir"
        case outputPath = "output_path"
        case status
        case errorMessage = "error_message"
        case createdAt = "created_at"
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
