import AppKit

/// Brings the main window forward and restores the Dock icon — shared by
/// Dock-icon reopen (`AppDelegate`) and the menu bar's "Show" item (Phase 6).
/// Copied from DKB Monitor's already-proven `native/` code (see Mục 1.5 in
/// docs/swift-native-port-plan.md).
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
