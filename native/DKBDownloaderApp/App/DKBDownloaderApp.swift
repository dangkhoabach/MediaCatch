import AppKit
import SwiftUI

@main
struct DKBDownloaderApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    private let windowDelegate = HideInsteadOfCloseDelegate()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .background(WindowAccessor(delegate: windowDelegate))
        }
        .commands {
            // Standard Sparkle placement: right under "About DKB Downloader"
            // in the app menu — matches lib.rs's Help-menu "Check for
            // Updates…" item in spirit, in the idiomatic macOS location.
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") {
                    AppUpdater.checkForUpdates()
                }
            }
        }

        MenuBarExtra("DKB Downloader", image: "TrayIcon") {
            MenuBarContentView()
        }
    }
}
