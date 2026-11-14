import AppKit
import SwiftUI

/// Brings the main window forward and restores the Dock icon — shared by
/// Dock-icon reopen (`AppDelegate`), the menu bar panel and Cmd+,.
/// Copied from SignalBar's already-proven code.
@MainActor
enum WindowPresenter {
    static let mainWindowID = "main"
    /// SwiftUI's own way to open the main window, kept by the status item
    /// (`OpenWindowKeeper`), for when there is no main window to bring forward.
    static var openWindow: OpenWindowAction?

    static func showMainWindow() {
        NSApp.setActivationPolicy(.regular)
        NSApp.unhide(nil)
        // A window SwiftUI never made at launch, or one that was closed for
        // good, is opened anew: bringing forward only the windows there are
        // left the app with a Dock icon and nothing to show.
        if mainWindows(in: NSApp.windows).isEmpty {
            openWindow?(id: mainWindowID)
        }
        for window in mainWindows(in: NSApp.windows) {
            window.makeKeyAndOrderFront(nil)
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Only the main window, recognised by the delegate `WindowAccessor`
    /// gives it: `NSApp.windows` also holds the menu bar panel and the About
    /// window, and ordering the panel front opens it outside the status
    /// item's own tracking, so it never closes.
    static func mainWindows(in windows: [NSWindow]) -> [NSWindow] {
        windows.filter { $0.delegate is HideInsteadOfCloseDelegate }
    }

    /// The Settings tab of the main window, the same destination as Cmd+,.
    static func showSettings() {
        AppNavigationState.shared.selectedSection = .settings
        showMainWindow()
    }
}

/// Keeps SwiftUI's `openWindow` for `WindowPresenter`. It sits, with no size,
/// in the status item, which is there from launch whether or not the main
/// window ever is.
struct OpenWindowKeeper: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onAppear { WindowPresenter.openWindow = openWindow }
    }
}
