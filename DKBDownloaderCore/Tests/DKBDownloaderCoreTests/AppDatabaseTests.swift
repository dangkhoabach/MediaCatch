import GRDB
import Testing
@testable import DKBDownloaderCore

struct AppDatabaseTests {
    @Test func createsFullSchemaOnAFreshDatabase() throws {
        let db = try AppDatabase(inMemory: try DatabaseQueue())
        try db.dbQueue.read { conn in
            for table in ["downloads", "watched_channels", "watched_channel_videos", "url_history"] {
                try #expect(conn.tableExists(table))
            }
        }
    }

    /// Simulates an existing Tauri-created DB (same schema, no GRDB history)
    /// to confirm the migrator is a correct no-op against it rather than
    /// erroring on tables that already exist.
    @Test func migratesCleanlyOverAnExistingTauriSchema() throws {
        let queue = try DatabaseQueue()
        try queue.write { db in
            try db.execute(sql: """
                CREATE TABLE downloads (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    url TEXT NOT NULL,
                    title TEXT NOT NULL,
                    format_selector TEXT NOT NULL,
                    output_dir TEXT NOT NULL,
                    output_path TEXT,
                    status TEXT NOT NULL DEFAULT 'downloading',
                    error_message TEXT,
                    created_at TEXT NOT NULL DEFAULT (datetime('now'))
                );
                INSERT INTO downloads (url, title, format_selector, output_dir, status)
                VALUES ('https://example.com/v', 'A video', 'best', '/tmp', 'completed');
                """)
        }

        let db = try AppDatabase(inMemory: queue)
        let count = try db.dbQueue.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM downloads") }
        #expect(count == 1)
    }
}
