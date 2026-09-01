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

    // `.preferredColorScheme(nil)` is meant to hand control back to the OS,
    // but on an already-visible NSWindow that previously had an explicit
    // scheme applied, SwiftUI doesn't reliably clear the appearance it set
    // under the hood - switching Dark/Light -> System silently no-ops.
    // Driving `NSApp.appearance` directly (nil = follow the system) doesn't
    // have that staleness problem.
    private func applyAppearance() {
        switch theme {
        case "light": NSApp.appearance = NSAppearance(named: .aqua)
        case "dark": NSApp.appearance = NSAppearance(named: .darkAqua)
        default: NSApp.appearance = nil
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(colorScheme)
                .background(WindowAccessor(delegate: windowDelegate))
                .onAppear { applyAppearance() }
                .onChange(of: theme) { _, _ in applyAppearance() }
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
