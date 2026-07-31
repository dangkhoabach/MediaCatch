use crate::models::DownloadRecord;
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
