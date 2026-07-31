mod db;
mod models;
mod notification;
mod ytdlp;

use rusqlite::Connection;
use std::collections::HashMap;
use std::sync::Mutex;
use tauri::menu::{Menu, MenuItem};
use tauri::tray::TrayIconBuilder;
use tauri::{Emitter, Manager, WebviewWindowBuilder, WindowEvent};
#[cfg(target_os = "macos")]
use tauri::{ActivationPolicy, LogicalPosition};
use tauri_plugin_shell::process::CommandChild;

pub struct AppState {
    pub db: Mutex<Connection>,
    pub children: Mutex<HashMap<i64, CommandChild>>,
    pub downloads_item: MenuItem<tauri::Wry>,
}

/// Keeps the tray menu's "Downloads: N" row in sync with how many are
/// actually running — called right after `children` changes (insert on
/// start, remove on cancel/finish) rather than polled, since download count
/// only ever changes at those exact points.
pub(crate) fn refresh_downloads_menu(app: &tauri::AppHandle) {
    let state = app.state::<AppState>();
    let count = state.children.lock().map(|c| c.len()).unwrap_or(0);
    let _ = state.downloads_item.set_text(format!("Downloads: {count}"));
}

/// Regular apps always count as foreground-capable to macOS even with zero
/// open windows, so hiding the window alone doesn't read as "running in the
/// background" — switching to Accessory (no Dock icon) while hidden is what
/// makes that distinction, and switching back to Regular restores the normal
/// Dock presence when the window reopens. Windows/Linux have no equivalent
/// concept — the tray icon alone is enough there.
pub(crate) fn show_main_window(app: &tauri::AppHandle) {
    #[cfg(target_os = "macos")]
    let _ = app.set_activation_policy(ActivationPolicy::Regular);
    if let Some(window) = app.get_webview_window("main") {
        let _ = window.show();
        let _ = window.set_focus();
    }
}

/// The macOS vibrancy blur is a native layer tied to the window's
/// NSAppearance, independent from our CSS theme class. Without this, picking
/// "light" in-app only recolors text/overlays while the native blur stays on
/// whatever appearance the window started with, making content unreadable.
#[tauri::command]
fn set_native_theme(window: tauri::Window, theme: String) -> Result<(), String> {
    let theme = match theme.as_str() {
        "light" => Some(tauri::Theme::Light),
        "dark" => Some(tauri::Theme::Dark),
        _ => None,
    };
    window.set_theme(theme).map_err(|e| e.to_string())
}

/// Generic notification entry point for the frontend — it owns the
/// "Notifications" on/off setting (see settings.ts), so this just shows
/// whatever it's asked to show without checking that itself.
#[tauri::command]
fn show_notification(
    app: tauri::AppHandle,
    title: String,
    body: String,
    route: Option<String>,
) -> Result<(), String> {
    notification::show(&app, &title, &body, route);
    Ok(())
}

/// tauri-plugin-notification's desktop backend always reports permission as
/// "Granted" regardless of the real OS state, so there's no reliable way to
/// detect denial from Rust. Instead of guessing, this deep-links straight to
/// this app's own Notifications settings pane so the user can check/grant it
/// themselves.
#[cfg(target_os = "macos")]
#[tauri::command]
fn open_notification_settings(app: tauri::AppHandle) -> Result<(), String> {
    let identifier = &app.config().identifier;
    std::process::Command::new("open")
        .arg(format!(
            "x-apple.systempreferences:com.apple.Notifications-Settings.extension?id={identifier}"
        ))
        .spawn()
        .map_err(|e| e.to_string())?;
    Ok(())
}

#[cfg(target_os = "windows")]
#[tauri::command]
fn open_notification_settings(_app: tauri::AppHandle) -> Result<(), String> {
    std::process::Command::new("explorer")
        .arg("ms-settings:notifications")
        .spawn()
        .map_err(|e| e.to_string())?;
    Ok(())
}

#[cfg(not(any(target_os = "macos", target_os = "windows")))]
#[tauri::command]
fn open_notification_settings(_app: tauri::AppHandle) -> Result<(), String> {
    Err("Not supported on this platform".into())
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_opener::init())
        .plugin(tauri_plugin_notification::init())
        .plugin(tauri_plugin_process::init())
        .plugin(tauri_plugin_dialog::init())
        .plugin(tauri_plugin_shell::init())
        .plugin(tauri_plugin_updater::Builder::new().build())
        .setup(|app| {
            let app_data_dir = app.path().app_data_dir()?;
            std::fs::create_dir_all(&app_data_dir)?;
            let db_path = app_data_dir.join("dkb-downloader.db");
            let conn = db::init_db(&db_path)?;
            let downloads_item = MenuItem::with_id(app, "downloads-stat", "Downloads: 0", false, None::<&str>)?;
            app.manage(AppState {
                db: Mutex::new(conn),
                children: Mutex::new(HashMap::new()),
                downloads_item: downloads_item.clone(),
            });

            // The "main" window is declared in tauri.conf.json with
            // "create": false so it's built here instead — there's no JSON
            // config option for traffic-light position, only this builder
            // method, and from_config() carries over every other window
            // setting (size, titleBarStyle, transparent...) unchanged.
            let main_window_config = app
                .config()
                .app
                .windows
                .iter()
                .find(|w| w.label == "main")
                .expect("main window must be declared in tauri.conf.json")
                .clone();
            let window_builder = WebviewWindowBuilder::from_config(app, &main_window_config)?;
            #[cfg(target_os = "macos")]
            let window_builder = window_builder.traffic_light_position(LogicalPosition::new(18.0, 22.0));
            window_builder.build()?;

            let show_item = MenuItem::with_id(app, "show", "Show DKB Downloader", true, None::<&str>)?;
            let quit_item = MenuItem::with_id(app, "quit", "Quit", true, None::<&str>)?;
            let separator = tauri::menu::PredefinedMenuItem::separator(app)?;
            let tray_menu = Menu::with_items(app, &[&downloads_item, &separator, &show_item, &quit_item])?;

            TrayIconBuilder::with_id("main-tray")
                .menu(&tray_menu)
                .icon(app.default_window_icon().unwrap().clone())
                .icon_as_template(true)
                .on_menu_event(|app, event| match event.id.as_ref() {
                    "show" => show_main_window(app),
                    "quit" => app.exit(0),
                    _ => {}
                })
                .build(app)?;

            // Start from Tauri's own platform-default menu (File/Edit/View/Window
            // as already shown) and only extend the Help submenu, so nothing
            // else about the native menu bar regresses.
            let app_menu = Menu::default(app.handle())?;
            for item in app_menu.items()? {
                if let Some(submenu) = item.as_submenu() {
                    if submenu.text()? == "Help" {
                        let check_update = MenuItem::with_id(
                            app,
                            "check-update",
                            "Check for Updates…",
                            true,
                            None::<&str>,
                        )?;
                        submenu.append(&tauri::menu::PredefinedMenuItem::separator(app)?)?;
                        submenu.append(&check_update)?;
                    }
                }
            }
            app.set_menu(app_menu)?;

            let update_app_handle = app.handle().clone();
            app.on_menu_event(move |app, event| {
                if event.id().as_ref() == "check-update" {
                    // The updater plugin's check/download/install flow runs
                    // entirely from the frontend (it needs a UI for progress
                    // and the restart prompt); this just brings the window
                    // forward and tells it to start.
                    show_main_window(app);
                    let _ = update_app_handle.emit("check-update-clicked", ());
                }
            });

            #[cfg(target_os = "macos")]
            {
                let window = app.get_webview_window("main").unwrap();
                window_vibrancy::apply_vibrancy(
                    &window,
                    window_vibrancy::NSVisualEffectMaterial::Sidebar,
                    None,
                    None,
                )
                .expect("failed to apply macOS vibrancy");
            }

            // Mica only exists on Windows 11 (window-vibrancy returns an Err
            // on Windows 10, unlike the macOS call above which is expected to
            // always succeed) — allowed to silently no-op over a purely
            // cosmetic effect rather than crashing the app.
            #[cfg(target_os = "windows")]
            {
                let window = app.get_webview_window("main").unwrap();
                let _ = window_vibrancy::apply_mica(&window, None);
            }

            Ok(())
        })
        .on_window_event(|window, event| {
            // Keep running in the tray instead of quitting when the window is
            // closed, so in-progress downloads keep running in the background.
            if let WindowEvent::CloseRequested { api, .. } = event {
                let _ = window.hide();
                #[cfg(target_os = "macos")]
                let _ = window.app_handle().set_activation_policy(ActivationPolicy::Accessory);
                api.prevent_close();
            }
        })
        .invoke_handler(tauri::generate_handler![
            ytdlp::fetch_video_info,
            ytdlp::start_download,
            ytdlp::cancel_download,
            ytdlp::pause_download,
            ytdlp::resume_download,
            ytdlp::list_downloads,
            ytdlp::delete_download_record,
            ytdlp::update_ytdlp,
            set_native_theme,
            show_notification,
            open_notification_settings,
        ])
        .build(tauri::generate_context!())
        .expect("error while building tauri application")
        .run(|_app_handle, _event| {
            // macOS sends this when the user reopens the app (Dock/Launchpad/
            // Finder) while it's already running — e.g. right after closing
            // the window, which only hides it and switches to Accessory mode
            // rather than quitting (see the CloseRequested handler above).
            #[cfg(target_os = "macos")]
            if let tauri::RunEvent::Reopen { .. } = _event {
                show_main_window(_app_handle);
            }
        });
}
