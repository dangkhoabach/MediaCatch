use tauri::menu::{Menu, MenuItem};
use tauri::tray::TrayIconBuilder;
use tauri::{Manager, WebviewWindowBuilder, WindowEvent};
#[cfg(target_os = "macos")]
use tauri::{ActivationPolicy, LogicalPosition};

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

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_opener::init())
        .plugin(tauri_plugin_notification::init())
        .plugin(tauri_plugin_process::init())
        .plugin(tauri_plugin_dialog::init())
        // tauri-plugin-updater is a Cargo dependency already (see Cargo.toml)
        // but isn't registered yet: it requires a non-null `plugins.updater`
        // config (endpoint + pubkey) or the app panics on launch. Wired up in
        // Phase 4 once the update distribution endpoint is decided.
        .setup(|app| {
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
            let tray_menu = Menu::with_items(app, &[&show_item, &quit_item])?;

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
