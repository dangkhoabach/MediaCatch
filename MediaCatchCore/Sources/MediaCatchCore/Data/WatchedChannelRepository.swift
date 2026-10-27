import Foundation
import GRDB

/// Mirrors db.rs's `watched_channels`/`watched_channel_videos`-table functions.
public struct WatchedChannelRepository: Sendable {
    let dbQueue: DatabaseQueue

    public init(dbQueue: DatabaseQueue) {
        self.dbQueue = dbQueue
    }

    @discardableResult
    public func insert(url: String, title: String, outputDir: String, outputFormat: String) throws -> Int64 {
        try dbQueue.write { db in
            var channel = WatchedChannel(url: url, title: title, outputDir: outputDir, outputFormat: outputFormat)
            try channel.insert(db)
            return channel.id!
        }
    }

    public func list() throws -> [WatchedChannel] {
        try dbQueue.read { db in try WatchedChannel.order(sql: "id DESC").fetchAll(db) }
    }

    /// Channels due for a poll: enabled, and either never checked yet or
    /// whose last check is older than their own configured interval.
    public func due() throws -> [WatchedChannel] {
        try dbQueue.read { db in
            try WatchedChannel.fetchAll(
                db,
                sql: """
                    SELECT * FROM watched_channels
                    WHERE enabled = 1 AND (
                        last_checked_at IS NULL
                        OR datetime(last_checked_at, '+' || interval_minutes || ' minutes') <= datetime('now')
                    )
                    """
            )
        }
    }

    public func touch(id: Int64) throws {
        try dbQueue.write { db in
            try db.execute(sql: "UPDATE watched_channels SET last_checked_at = datetime('now') WHERE id = ?", arguments: [id])
        }
    }

    public func setEnabled(id: Int64, enabled: Bool) throws {
        try dbQueue.write { db in
            try db.execute(sql: "UPDATE watched_channels SET enabled = ? WHERE id = ?", arguments: [enabled, id])
        }
    }

    public func remove(id: Int64) throws {
        try dbQueue.write { db in
            try db.execute(sql: "DELETE FROM watched_channels WHERE id = ?", arguments: [id])
            try db.execute(sql: "DELETE FROM watched_channel_videos WHERE channel_id = ?", arguments: [id])
        }
    }

    public func isVideoKnown(channelId: Int64, videoId: String) throws -> Bool {
        try dbQueue.read { db in
            try Bool.fetchOne(
                db,
                sql: "SELECT 1 FROM watched_channel_videos WHERE channel_id = ? AND video_id = ?",
                arguments: [channelId, videoId]
            ) ?? false
        }
    }

    public func markVideoKnown(channelId: Int64, videoId: String) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: "INSERT OR IGNORE INTO watched_channel_videos (channel_id, video_id) VALUES (?, ?)",
                arguments: [channelId, videoId]
            )
        }
    }
}
