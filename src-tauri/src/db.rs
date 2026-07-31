use crate::models::{DownloadRecord, WatchedChannel};
use rusqlite::{Connection, OptionalExtension};
use std::path::Path;

pub fn init_db(path: &Path) -> rusqlite::Result<Connection> {
    let conn = Connection::open(path)?;
    conn.execute_batch(
        "
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
        ",
    )?;
    Ok(conn)
}

pub fn insert_download(
    conn: &Connection,
    url: &str,
    title: &str,
    format_selector: &str,
    output_dir: &str,
) -> rusqlite::Result<i64> {
    conn.execute(
        "INSERT INTO downloads (url, title, format_selector, output_dir) VALUES (?1, ?2, ?3, ?4)",
        (url, title, format_selector, output_dir),
    )?;
    Ok(conn.last_insert_rowid())
}

pub fn set_status(
    conn: &Connection,
    id: i64,
    status: &str,
    error_message: Option<&str>,
) -> rusqlite::Result<()> {
    conn.execute(
        "UPDATE downloads SET status = ?1, error_message = ?2 WHERE id = ?3",
        (status, error_message, id),
    )?;
    Ok(())
}

pub fn set_output_path(conn: &Connection, id: i64, output_path: &str) -> rusqlite::Result<()> {
    conn.execute(
        "UPDATE downloads SET output_path = ?1 WHERE id = ?2",
        (output_path, id),
    )?;
    Ok(())
}

pub fn status(conn: &Connection, id: i64) -> rusqlite::Result<Option<String>> {
    conn.query_row("SELECT status FROM downloads WHERE id = ?1", [id], |row| row.get(0))
        .optional()
}

pub fn output_path(conn: &Connection, id: i64) -> rusqlite::Result<Option<String>> {
    conn.query_row(
        "SELECT output_path FROM downloads WHERE id = ?1",
        [id],
        |row| row.get(0),
    )
    .optional()
    .map(|v: Option<Option<String>>| v.flatten())
}

pub fn delete_download(conn: &Connection, id: i64) -> rusqlite::Result<()> {
    conn.execute("DELETE FROM downloads WHERE id = ?1", [id])?;
    Ok(())
}

pub fn list_downloads(conn: &Connection) -> rusqlite::Result<Vec<DownloadRecord>> {
    let mut stmt = conn.prepare(
        "SELECT id, url, title, format_selector, output_dir, output_path, status, error_message, created_at
         FROM downloads ORDER BY id DESC",
    )?;
    let rows = stmt.query_map([], |row| {
        Ok(DownloadRecord {
            id: row.get(0)?,
            url: row.get(1)?,
            title: row.get(2)?,
            format_selector: row.get(3)?,
            output_dir: row.get(4)?,
            output_path: row.get(5)?,
            status: row.get(6)?,
            error_message: row.get(7)?,
            created_at: row.get(8)?,
        })
    })?;
    rows.collect()
}

pub fn insert_watched_channel(
    conn: &Connection,
    url: &str,
    title: &str,
    output_dir: &str,
    output_format: &str,
) -> rusqlite::Result<i64> {
    conn.execute(
        "INSERT INTO watched_channels (url, title, output_dir, output_format) VALUES (?1, ?2, ?3, ?4)",
        (url, title, output_dir, output_format),
    )?;
    Ok(conn.last_insert_rowid())
}

fn map_watched_channel(row: &rusqlite::Row) -> rusqlite::Result<WatchedChannel> {
    Ok(WatchedChannel {
        id: row.get(0)?,
        url: row.get(1)?,
        title: row.get(2)?,
        enabled: row.get::<_, i64>(3)? != 0,
        interval_minutes: row.get(4)?,
        output_dir: row.get(5)?,
        output_format: row.get(6)?,
        last_checked_at: row.get(7)?,
        created_at: row.get(8)?,
    })
}

const WATCHED_CHANNEL_COLUMNS: &str =
    "id, url, title, enabled, interval_minutes, output_dir, output_format, last_checked_at, created_at";

pub fn list_watched_channels(conn: &Connection) -> rusqlite::Result<Vec<WatchedChannel>> {
    let mut stmt = conn.prepare(&format!(
        "SELECT {WATCHED_CHANNEL_COLUMNS} FROM watched_channels ORDER BY id DESC"
    ))?;
    let rows = stmt.query_map([], map_watched_channel)?;
    rows.collect()
}

/// Channels due for a poll: enabled, and either never checked yet or whose
/// last check is older than their own configured interval.
pub fn due_watched_channels(conn: &Connection) -> rusqlite::Result<Vec<WatchedChannel>> {
    let mut stmt = conn.prepare(&format!(
        "SELECT {WATCHED_CHANNEL_COLUMNS} FROM watched_channels
         WHERE enabled = 1 AND (
             last_checked_at IS NULL
             OR datetime(last_checked_at, '+' || interval_minutes || ' minutes') <= datetime('now')
         )"
    ))?;
    let rows = stmt.query_map([], map_watched_channel)?;
    rows.collect()
}

pub fn touch_watched_channel(conn: &Connection, id: i64) -> rusqlite::Result<()> {
    conn.execute(
        "UPDATE watched_channels SET last_checked_at = datetime('now') WHERE id = ?1",
        [id],
    )?;
    Ok(())
}

pub fn set_watched_channel_enabled(conn: &Connection, id: i64, enabled: bool) -> rusqlite::Result<()> {
    conn.execute(
        "UPDATE watched_channels SET enabled = ?1 WHERE id = ?2",
        (enabled as i64, id),
    )?;
    Ok(())
}

pub fn remove_watched_channel(conn: &Connection, id: i64) -> rusqlite::Result<()> {
    conn.execute("DELETE FROM watched_channels WHERE id = ?1", [id])?;
    conn.execute("DELETE FROM watched_channel_videos WHERE channel_id = ?1", [id])?;
    Ok(())
}

pub fn is_video_known(conn: &Connection, channel_id: i64, video_id: &str) -> rusqlite::Result<bool> {
    conn.query_row(
        "SELECT 1 FROM watched_channel_videos WHERE channel_id = ?1 AND video_id = ?2",
        (channel_id, video_id),
        |_| Ok(()),
    )
    .optional()
    .map(|r| r.is_some())
}

pub fn mark_video_known(conn: &Connection, channel_id: i64, video_id: &str) -> rusqlite::Result<()> {
    conn.execute(
        "INSERT OR IGNORE INTO watched_channel_videos (channel_id, video_id) VALUES (?1, ?2)",
        (channel_id, video_id),
    )?;
    Ok(())
}
