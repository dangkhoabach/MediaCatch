import Foundation
import GRDB

/// Mirrors db.rs's `downloads`-table functions.
public struct DownloadRepository: Sendable {
    let dbQueue: DatabaseQueue

    public init(dbQueue: DatabaseQueue) {
        self.dbQueue = dbQueue
    }

    @discardableResult
    public func insert(url: String, title: String, formatSelector: String, outputDir: String) throws -> Int64 {
        try dbQueue.write { db in
            var download = Download(url: url, title: title, formatSelector: formatSelector, outputDir: outputDir)
            try download.insert(db)
            return download.id!
        }
    }

    public func setStatus(id: Int64, status: DownloadStatus, errorMessage: String? = nil) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: "UPDATE downloads SET status = ?, error_message = ? WHERE id = ?",
                arguments: [status.rawValue, errorMessage, id]
            )
        }
    }

    public func setOutputPath(id: Int64, outputPath: String) throws {
        try dbQueue.write { db in
            try db.execute(sql: "UPDATE downloads SET output_path = ? WHERE id = ?", arguments: [outputPath, id])
        }
    }

    public func status(id: Int64) throws -> DownloadStatus? {
        try dbQueue.read { db in
            try String.fetchOne(db, sql: "SELECT status FROM downloads WHERE id = ?", arguments: [id])
                .flatMap(DownloadStatus.init(rawValue:))
        }
    }

    public func outputPath(id: Int64) throws -> String? {
        try dbQueue.read { db in
            try String.fetchOne(db, sql: "SELECT output_path FROM downloads WHERE id = ?", arguments: [id])
        }
    }

    /// Written into `error_message` by `reconcileInterrupted` instead of a
    /// human-readable sentence: Core has no business choosing the user's
    /// language, so the App layer maps this marker to a localized string when
    /// it displays the row.
    public static let interruptedErrorMessage = "dkb.error.interrupted"

    /// Marks every row still `.downloading` as `.error` — called once at
    /// startup. A row can only be `.downloading` at launch if the app was
    /// killed/crashed mid-download last time: there's no live `ProcessRunner`
    /// for it in this fresh process, so without this it stays stuck showing
    /// "downloading" forever with Cancel/Pause as permanent no-ops.
    public func reconcileInterrupted() throws {
        try dbQueue.write { db in
            try db.execute(
                sql: "UPDATE downloads SET status = ?, error_message = ? WHERE status = ?",
                arguments: [DownloadStatus.error.rawValue, Self.interruptedErrorMessage, DownloadStatus.downloading.rawValue]
            )
        }
    }

    public func delete(id: Int64) throws {
        _ = try dbQueue.write { db in try Download.deleteOne(db, key: id) }
    }

    public func list() throws -> [Download] {
        try dbQueue.read { db in try Download.order(sql: "id DESC").fetchAll(db) }
    }
}
