import AppKit
import SwiftUI

@main
struct DKBDownloaderApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @AppStorage("dkb-downloader:theme") private var theme = "system"
    private let windowDelegate = HideInsteadOfCloseDelegate()

    private var colorScheme: ColorScheme? {
        switch theme {
        case "light": return .light
        case "dark": return .dark
        default: return nil
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(colorScheme)
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
            // Replaces the default Cmd+, action (which would normally open a
            // separate `Settings {}` scene/window). There's no such scene
            // any more — Settings is just another sidebar tab in the main
            // window (see ContentView), so Cmd+, brings that window forward
            // and selects the same tab the menu bar tray's "Settings…" item
            // does, instead of opening a second window.
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") {
                    AppNavigationState.shared.selectedSection = .settings
                    WindowPresenter.showMainWindow()
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }

        MenuBarExtra("DKB Downloader", systemImage: "arrow.down.circle") {
            MenuBarContentView()
        }
    }
}
