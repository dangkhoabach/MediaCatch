import Foundation
import GRDB

/// Opens (or creates) the app's SQLite database and keeps it migrated.
///
/// Per D4 in the plan: this reads the **same file** the Tauri app already
/// uses (same bundle id, see D2), so `migrator` must both (a) create the
/// full schema from scratch on a brand-new install, and (b) be a correct
/// no-op against an existing Tauri-created DB (which predates GRDB
/// entirely). Both paths are exercised in `AppDatabaseTests`.
public struct AppDatabase: Sendable {
    public let dbQueue: DatabaseQueue

    public init(path: String) throws {
        dbQueue = try DatabaseQueue(path: path)
        try Self.migrator.migrate(dbQueue)
    }

    /// In-memory database for tests/previews.
    public init(inMemory: DatabaseQueue) throws {
        dbQueue = inMemory
        try Self.migrator.migrate(dbQueue)
    }

    static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()

        // Mirrors db.rs::init_db exactly, so this step is a correct no-op
        // against an existing Tauri-created DB and a correct fresh create
        // otherwise.
        migrator.registerMigration("v1_baselineSchema") { db in
            try db.execute(sql: """
                CREATE TABLE IF NOT EXISTS downloads (
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

                CREATE TABLE IF NOT EXISTS watched_channels (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    url TEXT NOT NULL,
                    title TEXT NOT NULL,
                    enabled INTEGER NOT NULL DEFAULT 1,
                    interval_minutes INTEGER NOT NULL DEFAULT 30,
                    output_dir TEXT NOT NULL,
                    output_format TEXT NOT NULL,
                    last_checked_at TEXT,
                    created_at TEXT NOT NULL DEFAULT (datetime('now'))
                );

                CREATE TABLE IF NOT EXISTS watched_channel_videos (
                    channel_id INTEGER NOT NULL,
                    video_id TEXT NOT NULL,
                    PRIMARY KEY (channel_id, video_id)
                );

                CREATE TABLE IF NOT EXISTS url_history (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    url TEXT NOT NULL UNIQUE,
                    title TEXT NOT NULL,
                    fetch_count INTEGER NOT NULL DEFAULT 1,
                    last_fetched_at TEXT NOT NULL DEFAULT (datetime('now'))
                );
                """)
        }

        return migrator
    }
}
