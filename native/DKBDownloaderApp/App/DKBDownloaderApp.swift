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

        // Real "Downloads: N" content + Show/Quit lands in Phase 6 — this is
        // just enough to confirm MenuBarExtra coexists with WindowGroup and
        // the app doesn't crash.
        MenuBarExtra("DKB Downloader", systemImage: "arrow.down.circle") {
            Button("Quit") {
                NSApp.terminate(nil)
            }
        }
    }
}
