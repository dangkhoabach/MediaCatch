import AppKit

/// Brings the main window forward and restores the Dock icon — shared by
/// Dock-icon reopen (`AppDelegate`) and the menu bar's "Show" item.
/// Copied from DKB Monitor's already-proven code.
@MainActor
enum WindowPresenter {
    static func showMainWindow() {
        NSApp.setActivationPolicy(.regular)
        NSApp.unhide(nil)
        for window in NSApp.windows {
            window.makeKeyAndOrderFront(nil)
        }
        NSApp.activate(ignoringOtherApps: true)
    }
}
