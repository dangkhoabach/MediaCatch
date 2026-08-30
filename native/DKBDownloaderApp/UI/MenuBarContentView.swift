import AppKit
import SwiftUI

/// Mirrors the Tauri tray menu (`lib.rs`): a live "Downloads: N" row, then
/// Show/Quit.
struct MenuBarContentView: View {
    var body: some View {
        Text("Downloads: \(MenuBarStatsViewModel.shared.activeDownloadCount)")

        Divider()

        Button("Show DKB Downloader") {
            WindowPresenter.showMainWindow()
        }
        // Same tab as the app menu's Cmd+, (see DKBDownloaderApp.swift) —
        // both entry points select ContentView's one Settings tab in the
        // main window instead of opening a separate window.
        Button("Settings…") {
            AppNavigationState.shared.selectedSection = .settings
            WindowPresenter.showMainWindow()
        }
        Button("Quit") {
            NSApp.terminate(nil)
        }
    }
}
