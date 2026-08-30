import AppKit

/// Minimal AppKit glue for the 2 behaviors SwiftUI Scenes don't expose (see
/// D5/Mục 2 in docs/swift-native-port-plan.md, copied from DKB Monitor's
/// already-proven native/ code): keep running after the last window closes,
/// and reopen on Dock click.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        MenuBarStatsViewModel.shared.start()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        WindowPresenter.showMainWindow()
        return true
    }
}
