import Foundation
import GRDB

/// Mirrors db.rs's `url_history`-table functions — one row per distinct URL,
/// bumping `fetch_count`/`last_fetched_at` on repeat fetches instead of
/// growing unbounded.
public struct UrlHistoryRepository: Sendable {
    let dbQueue: DatabaseQueue

    public init(dbQueue: DatabaseQueue) {
        self.dbQueue = dbQueue
    }

    public func upsert(url: String, title: String) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: """
                    INSERT INTO url_history (url, title) VALUES (?, ?)
                    ON CONFLICT(url) DO UPDATE SET
                        title = excluded.title,
                        fetch_count = fetch_count + 1,
                        last_fetched_at = datetime('now')
                    """,
                arguments: [url, title]
            )
        }
    }

    public func list(limit: Int = 200) throws -> [UrlHistoryEntry] {
        try dbQueue.read { db in
            try UrlHistoryEntry.fetchAll(
                db,
                sql: "SELECT * FROM url_history ORDER BY last_fetched_at DESC LIMIT ?",
                arguments: [limit]
            )
        }
    }

    public func delete(id: Int64) throws {
        _ = try dbQueue.write { db in try UrlHistoryEntry.deleteOne(db, key: id) }
    }

    public func clear() throws {
        _ = try dbQueue.write { db in try UrlHistoryEntry.deleteAll(db) }
    }
}
