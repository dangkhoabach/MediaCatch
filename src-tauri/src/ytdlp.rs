use crate::models::{DownloadProgress, DownloadRecord, VideoInfo, YtDlpInfo};
use crate::{db, AppState};
use serde::Deserialize;
use tauri::{AppHandle, Emitter, Manager, State};
use tauri_plugin_shell::process::{Command, CommandEvent};
use tauri_plugin_shell::ShellExt;

#[cfg(windows)]
fn ytdlp_binary_name() -> &'static str {
    "yt-dlp.exe"
}
#[cfg(not(windows))]
fn ytdlp_binary_name() -> &'static str {
    "yt-dlp"
}

/// Prefers a copy previously fetched by `update_ytdlp` into the app data dir
/// (kept up to date independently of app releases) over the bundled sidecar
/// seed binary, which only exists so the app works offline on first run.
fn ytdlp_command(app: &AppHandle) -> Command {
    if let Ok(updated) = app
        .path()
        .app_data_dir()
        .map(|dir| dir.join("bin").join(ytdlp_binary_name()))
    {
        if updated.exists() {
            return app.shell().command(updated);
        }
    }
    app.shell()
        .sidecar("yt-dlp")
        .expect("yt-dlp sidecar binary not bundled — run scripts/fetch-ytdlp.sh")
}

#[tauri::command]
pub async fn fetch_video_info(app: AppHandle, url: String) -> Result<VideoInfo, String> {
    let output = ytdlp_command(&app)
        .args(["-j", "--no-playlist", "--no-warnings", &url])
        .output()
        .await
        .map_err(|e| e.to_string())?;

    if !output.status.success() {
        return Err(String::from_utf8_lossy(&output.stderr).trim().to_string());
    }

    let info: YtDlpInfo = serde_json::from_slice(&output.stdout).map_err(|e| e.to_string())?;
    Ok(info.into())
}

#[tauri::command]
pub async fn start_download(
    app: AppHandle,
    state: State<'_, AppState>,
    url: String,
    title: String,
    format_selector: String,
    output_dir: String,
    output_format: String,
) -> Result<i64, String> {
    let download_id = {
        let conn = state.db.lock().map_err(|e| e.to_string())?;
        db::insert_download(&conn, &url, &title, &format_selector, &output_dir)
            .map_err(|e| e.to_string())?
    };

    let output_template = format!("{output_dir}/%(title)s.%(ext)s");
    let (mut rx, child) = ytdlp_command(&app)
        .args([
            "-f",
            &format_selector,
            "--merge-output-format",
            &output_format,
            "-o",
            &output_template,
            "--quiet",
            "--no-warnings",
            // `--progress` forces the progress bar even though our stdout is
            // a pipe, not a tty — yt-dlp otherwise silently skips it entirely
            // in that case, no matter what --progress-template is set to.
            "--progress",
            "--newline",
            // The "download:" prefix is yt-dlp's TYPE selector (which event
            // this template applies to), not literal output — the printed
            // line is just the template text, so it needs its own marker
            // ("DKB|") to be distinguishable from the final --print line below.
            "--progress-template",
            "download:DKB|%(progress._percent_str)s|%(progress._speed_str)s|%(progress._eta_str)s",
            // Prints the final merged file's real path as the last line of
            // output, once post-processing is done — used to populate
            // output_path for "open file" in the library view.
            "--print",
            "after_move:filepath",
            &url,
        ])
        .spawn()
        .map_err(|e| e.to_string())?;

    state
        .children
        .lock()
        .map_err(|e| e.to_string())?
        .insert(download_id, child);
    crate::refresh_downloads_menu(&app);

    let app_handle = app.clone();
    tauri::async_runtime::spawn(async move {
        let mut output_path: Option<String> = None;
        let mut last_error: Option<String> = None;
        while let Some(event) = rx.recv().await {
            match event {
                CommandEvent::Stdout(bytes) => {
                    let line = String::from_utf8_lossy(&bytes);
                    let line = line.trim();
                    if let Some(rest) = line.strip_prefix("DKB|") {
                        let mut parts = rest.splitn(3, '|');
                        let progress = DownloadProgress {
                            download_id,
                            percent: parts.next().unwrap_or_default().trim().to_string(),
                            speed: parts.next().unwrap_or_default().trim().to_string(),
                            eta: parts.next().unwrap_or_default().trim().to_string(),
                        };
                        let _ = app_handle.emit("download-progress", progress);
                    } else if !line.is_empty() {
                        // With --quiet --no-warnings, the only other stdout
                        // line is the `--print after_move:filepath` output.
                        output_path = Some(line.to_string());
                    }
                }
                CommandEvent::Stderr(bytes) => {
                    let line = String::from_utf8_lossy(&bytes).trim().to_string();
                    if !line.is_empty() {
                        last_error = Some(line);
                    }
                }
                CommandEvent::Terminated(payload) => {
                    let success = payload.code == Some(0);
                    let app_state = app_handle.state::<AppState>();
                    // cancel_download already marks the row "canceled" and
                    // removes the child synchronously — this Terminated event
                    // still arrives afterwards (killing the process triggers
                    // it too), so it must not clobber that with "error".
                    let was_canceled = app_state
                        .db
                        .lock()
                        .ok()
                        .and_then(|conn| db::status(&conn, download_id).ok().flatten())
                        .as_deref()
                        == Some("canceled");

                    if !was_canceled {
                        if let Ok(conn) = app_state.db.lock() {
                            let _ = db::set_status(
                                &conn,
                                download_id,
                                if success { "completed" } else { "error" },
                                if success { None } else { last_error.as_deref() },
                            );
                            if let Some(path) = &output_path {
                                let _ = db::set_output_path(&conn, download_id, path);
                            }
                        }
                    }
                    if let Ok(mut children) = app_state.children.lock() {
                        children.remove(&download_id);
                    }
                    crate::refresh_downloads_menu(&app_handle);
                    if !was_canceled {
                        let event_name = if success {
                            "download-complete"
                        } else {
                            "download-error"
                        };
                        let _ = app_handle.emit(event_name, download_id);
                    }
                    break;
                }
                _ => {}
            }
        }
    });

    Ok(download_id)
}

#[tauri::command]
pub fn cancel_download(app: AppHandle, state: State<'_, AppState>, download_id: i64) -> Result<(), String> {
    let mut children = state.children.lock().map_err(|e| e.to_string())?;
    if let Some(child) = children.remove(&download_id) {
        child.kill().map_err(|e| e.to_string())?;
    }
    drop(children);
    crate::refresh_downloads_menu(&app);
    let conn = state.db.lock().map_err(|e| e.to_string())?;
    db::set_status(&conn, download_id, "canceled", None).map_err(|e| e.to_string())
}

/// yt-dlp has no built-in pause; suspending/resuming the OS process itself
/// (SIGSTOP/SIGCONT) just stalls its network reads mid-stream, which is
/// enough since the partial file and connection stay intact. Windows has no
/// signal equivalent, so it's unsupported there for now (macOS is the
/// priority platform for this app).
#[cfg(unix)]
#[tauri::command]
pub fn pause_download(state: State<'_, AppState>, download_id: i64) -> Result<(), String> {
    send_signal(&state, download_id, "STOP")
}

#[cfg(unix)]
#[tauri::command]
pub fn resume_download(state: State<'_, AppState>, download_id: i64) -> Result<(), String> {
    send_signal(&state, download_id, "CONT")
}

#[cfg(unix)]
fn send_signal(state: &State<'_, AppState>, download_id: i64, signal: &str) -> Result<(), String> {
    let children = state.children.lock().map_err(|e| e.to_string())?;
    let child = children
        .get(&download_id)
        .ok_or("download not found or already finished")?;
    let status = std::process::Command::new("kill")
        .arg(format!("-{signal}"))
        .arg(child.pid().to_string())
        .status()
        .map_err(|e| e.to_string())?;
    if status.success() {
        Ok(())
    } else {
        Err(format!("kill -{signal} on pid {} failed", child.pid()))
    }
}

#[cfg(windows)]
#[tauri::command]
pub fn pause_download(_state: State<'_, AppState>, _download_id: i64) -> Result<(), String> {
    Err("Pause/resume isn't supported on Windows yet".into())
}

#[cfg(windows)]
#[tauri::command]
pub fn resume_download(_state: State<'_, AppState>, _download_id: i64) -> Result<(), String> {
    Err("Pause/resume isn't supported on Windows yet".into())
}

#[tauri::command]
pub fn list_downloads(state: State<'_, AppState>) -> Result<Vec<DownloadRecord>, String> {
    let conn = state.db.lock().map_err(|e| e.to_string())?;
    db::list_downloads(&conn).map_err(|e| e.to_string())
}

#[tauri::command]
pub fn delete_download_record(
    state: State<'_, AppState>,
    download_id: i64,
    delete_file: bool,
) -> Result<(), String> {
    let conn = state.db.lock().map_err(|e| e.to_string())?;
    if delete_file {
        if let Some(path) = db::output_path(&conn, download_id).map_err(|e| e.to_string())? {
            let _ = std::fs::remove_file(path);
        }
    }
    db::delete_download(&conn, download_id).map_err(|e| e.to_string())
}

#[derive(Deserialize)]
struct GithubRelease {
    tag_name: String,
}

#[cfg(target_os = "macos")]
fn ytdlp_release_asset_name() -> &'static str {
    "yt-dlp_macos"
}
#[cfg(windows)]
fn ytdlp_release_asset_name() -> &'static str {
    "yt-dlp.exe"
}

/// Checks GitHub for a newer yt-dlp release than the one currently in use
/// and, if found, downloads it into the app data dir — independent of this
/// app's own release cycle, so YouTube extractor breakage gets fixed as
/// soon as upstream ships a fix rather than waiting on an app update.
/// Returns `Ok(None)` when already up to date, `Ok(Some(new_version))` when
/// it just updated — callers use this to decide whether a notification is
/// warranted.
#[tauri::command]
pub async fn update_ytdlp(app: AppHandle) -> Result<Option<String>, String> {
    let current = ytdlp_command(&app)
        .args(["--version"])
        .output()
        .await
        .map_err(|e| e.to_string())?;
    let current_version = String::from_utf8_lossy(&current.stdout).trim().to_string();

    let client = reqwest::Client::builder()
        .user_agent("DKB-Downloader")
        .build()
        .map_err(|e| e.to_string())?;
    let release: GithubRelease = client
        .get("https://api.github.com/repos/yt-dlp/yt-dlp/releases/latest")
        .send()
        .await
        .map_err(|e| e.to_string())?
        .json()
        .await
        .map_err(|e| e.to_string())?;

    if release.tag_name == current_version {
        return Ok(None);
    }

    let asset_url = format!(
        "https://github.com/yt-dlp/yt-dlp/releases/download/{}/{}",
        release.tag_name,
        ytdlp_release_asset_name()
    );
    let bytes = client
        .get(&asset_url)
        .send()
        .await
        .map_err(|e| e.to_string())?
        .bytes()
        .await
        .map_err(|e| e.to_string())?;

    let bin_dir = app
        .path()
        .app_data_dir()
        .map_err(|e| e.to_string())?
        .join("bin");
    std::fs::create_dir_all(&bin_dir).map_err(|e| e.to_string())?;
    let bin_path = bin_dir.join(ytdlp_binary_name());
    std::fs::write(&bin_path, &bytes).map_err(|e| e.to_string())?;

    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        std::fs::set_permissions(&bin_path, std::fs::Permissions::from_mode(0o755))
            .map_err(|e| e.to_string())?;
    }

    Ok(Some(release.tag_name))
}
