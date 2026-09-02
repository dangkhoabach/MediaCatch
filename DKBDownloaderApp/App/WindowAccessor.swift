import AppKit
import SwiftUI

/// Intercepts the red close button to hide the window instead of destroying
/// it, and switches the Dock icon to Accessory — matches the Tauri version's
/// `WindowEvent::CloseRequested` handling (`window.hide()` + `prevent_close()`
/// + `ActivationPolicy::Accessory`) so in-progress downloads keep running in
/// the background instead of the app quitting. Copied verbatim from DKB
/// Monitor's already-proven `native/` code (Mục 1.5 in
/// docs/swift-native-port-plan.md) — same behavior, different app.
final class HideInsteadOfCloseDelegate: NSObject, NSWindowDelegate {
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        // `sender.orderOut(nil)` alone leaves the NSWindow object alive but
        // invisible - macOS still counts it as an open window, so switching
        // to .accessory right after leaves Stage Manager showing a ghost
        // tile for a window with no visible content. `NSApp.hide(nil)` is
        // the same mechanism as Cmd+H: the whole app (and its windows) is
        // excluded from Stage Manager/Mission Control/Cmd+Tab while hidden,
        // which is what "hide instead of close" actually needs here.
        NSApp.hide(nil)
        NSApp.setActivationPolicy(.accessory)
        return false
    }
}

/// SwiftUI's `WindowGroup` exposes no API for hide-not-quit, a transparent
/// titlebar, or a custom traffic-light position — this reaches into AppKit
/// once via `NSViewRepresentable` to grab the real `NSWindow` and configure
/// all 3, matching the window chrome this app currently ships with via Tauri
/// (`titleBarStyle: "Overlay"`, `hiddenTitle: true`, `transparent: true`,
/// `traffic_light_position(18, 22)` in tauri.conf.json).
struct WindowAccessor: NSViewRepresentable {
    let delegate: HideInsteadOfCloseDelegate

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            window.delegate = delegate
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.styleMask.insert(.fullSizeContentView)
            Self.repositionTrafficLights(in: window, x: 18, y: 22)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    /// `x`/`y` mirror Tauri's `LogicalPosition` argument to
    /// `traffic_light_position` — offset from the titlebar's top-left corner
    /// to the *center* of the leftmost (close) button. `spacing` (20pt) is
    /// AppKit's own standard gap between the 3 buttons, left unchanged.
    ///
    /// NOTE: not yet visually confirmed 
    /// — needs a manual look before Phase 8 relies on it.
    private static func repositionTrafficLights(in window: NSWindow, x: CGFloat, y: CGFloat) {
        let buttonTypes: [NSWindow.ButtonType] = [.closeButton, .miniaturizeButton, .zoomButton]
        let buttons = buttonTypes.compactMap { window.standardWindowButton($0) }
        guard buttons.count == 3, let titlebarView = buttons[0].superview else { return }

        let spacing: CGFloat = 20
        for (index, button) in buttons.enumerated() {
            var frame = button.frame
            frame.origin.x = x - frame.width / 2 + CGFloat(index) * spacing
            frame.origin.y = titlebarView.frame.height - y - frame.height / 2
            button.frame = frame
        }
    }
}
