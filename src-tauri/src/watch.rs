use crate::models::WatchedChannel;
use crate::{db, ytdlp, AppState};
use tauri::{AppHandle, Emitter, Manager, State};

/// Registers a channel/playlist URL for monitoring. The current entries are
/// recorded as already-known so the very first poll only reacts to videos
/// uploaded *after* this point, instead of bulk-downloading the channel's
/// entire back catalog the moment it's added.
#[tauri::command]
pub async fn add_watched_channel(
    app: AppHandle,
    state: State<'_, AppState>,
    url: String,
    output_dir: String,
    output_format: String,
) -> Result<WatchedChannel, String> {
    let dump = ytdlp::dump_playlist(&app, &url, Some(5)).await?;
    let title = dump.title.unwrap_or_else(|| url.clone());

    let channel_id = {
        let conn = state.db.lock().map_err(|e| e.to_string())?;
        let id = db::insert_watched_channel(&conn, &url, &title, &output_dir, &output_format)
            .map_err(|e| e.to_string())?;
        for entry in &dump.entries {
            db::mark_video_known(&conn, id, &entry.id).map_err(|e| e.to_string())?;
        }
        db::touch_watched_channel(&conn, id).map_err(|e| e.to_string())?;
        id
    };

    let conn = state.db.lock().map_err(|e| e.to_string())?;
    db::list_watched_channels(&conn)
        .map_err(|e| e.to_string())?
        .into_iter()
        .find(|c| c.id == channel_id)
        .ok_or_else(|| "channel disappeared right after insert".to_string())
}

#[tauri::command]
pub fn list_watched_channels(state: State<'_, AppState>) -> Result<Vec<WatchedChannel>, String> {
    let conn = state.db.lock().map_err(|e| e.to_string())?;
    db::list_watched_channels(&conn).map_err(|e| e.to_string())
}

#[tauri::command]
pub fn remove_watched_channel(state: State<'_, AppState>, id: i64) -> Result<(), String> {
    let conn = state.db.lock().map_err(|e| e.to_string())?;
    db::remove_watched_channel(&conn, id).map_err(|e| e.to_string())
}

#[tauri::command]
pub fn set_watched_channel_enabled(state: State<'_, AppState>, id: i64, enabled: bool) -> Result<(), String> {
    let conn = state.db.lock().map_err(|e| e.to_string())?;
    db::set_watched_channel_enabled(&conn, id, enabled).map_err(|e| e.to_string())
}

/// Runs one polling pass over every channel whose interval has elapsed.
/// Called from a background loop in `lib.rs`'s `setup`, never from the
/// frontend directly. New videos are downloaded at a fixed sane default
/// quality (best video+audio) — per-download choices like embed-metadata,
/// cookies-from-browser or aria2c don't apply here since there's no UI
/// interaction at poll time to source them from.
pub async fn poll_due_channels(app: &AppHandle) {
    let due = {
        let state = app.state::<AppState>();
        let Ok(conn) = state.db.lock() else { return };
        db::due_watched_channels(&conn).unwrap_or_default()
    };

    for channel in due {
        let dump = match ytdlp::dump_playlist(app, &channel.url, Some(5)).await {
            Ok(dump) => dump,
            Err(_) => continue, // transient network/extractor error — retry next tick
        };

        for entry in dump.entries.iter().rev() {
            let already_known = {
                let state = app.state::<AppState>();
                let Ok(conn) = state.db.lock() else { continue };
                db::is_video_known(&conn, channel.id, &entry.id).unwrap_or(true)
            };
            if already_known {
                continue;
            }

            let Some(video_url) = entry.url.clone() else { continue };
            let title = entry.title.clone().unwrap_or_else(|| entry.id.clone());

            {
                let state = app.state::<AppState>();
                let Ok(conn) = state.db.lock() else { continue };
                let _ = db::mark_video_known(&conn, channel.id, &entry.id);
            }

            let state = app.state::<AppState>();
            let result = ytdlp::start_download(
                app.clone(),
                state,
                video_url,
                title.clone(),
                "bestvideo*+bestaudio/best".into(),
                channel.output_dir.clone(),
                channel.output_format.clone(),
                false,
                None,
                false,
            )
            .await;

            if result.is_ok() {
                let _ = app.emit(
                    "watched-new-video",
                    serde_json::json!({ "channelTitle": channel.title, "videoTitle": title }),
                );
            }
        }

        let state = app.state::<AppState>();
        let Ok(conn) = state.db.lock() else { continue };
        let _ = db::touch_watched_channel(&conn, channel.id);
    }
}
