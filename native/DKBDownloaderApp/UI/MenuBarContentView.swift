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
        Button("Quit") {
            NSApp.terminate(nil)
        }
    }
}
