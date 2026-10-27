import AppKit
import SwiftUI

/// Mirrors the Tauri tray menu (`lib.rs`): a live "Downloads: N" row, then
/// Show/Quit.
struct MenuBarContentView: View {
    var body: some View {
        // `t()` rather than a bare string literal: SwiftUI would localize a
        // literal against the *system* language, ignoring the language picker
        // in Settings that every other surface follows.
        Text(t("menubar.downloads", ["count": "\(MenuBarStatsViewModel.shared.activeDownloadCount)"]))

        Divider()

        Button(t("menubar.show")) {
            WindowPresenter.showMainWindow()
        }
        // Same tab as the app menu's Cmd+, (see MediaCatchApp.swift) —
        // both entry points select ContentView's one Settings tab in the
        // main window instead of opening a separate window.
        Button(t("menubar.settings")) {
            AppNavigationState.shared.selectedSection = .settings
            WindowPresenter.showMainWindow()
        }
        Button(t("menubar.quit")) {
            NSApp.terminate(nil)
        }
    }
}
