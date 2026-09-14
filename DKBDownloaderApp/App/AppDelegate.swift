import AppKit
import DKBDownloaderCore

/// Minimal AppKit glue for the 2 behaviors SwiftUI Scenes don't expose (see
/// D5/Mục 2 in docs/swift-native-port-plan.md, copied from DKB Monitor's
/// already-proven native/ code): keep running after the last window closes,
/// and reopen on Dock click.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        MenuBarStatsViewModel.shared.start()
        BackgroundServices.start()
        presentDatabaseRecoveryAlertIfNeeded()
    }

    /// The database file couldn't be opened this launch and had to be
    /// replaced — say so once, so the resulting empty history reads as a
    /// recovery rather than the app silently losing everything.
    @MainActor
    private func presentDatabaseRecoveryAlertIfNeeded() {
        // Touch `shared` first: it's lazily initialized and `recovery` only
        // gets set while that initializer runs, which nothing above is
        // guaranteed to have triggered yet (both start() calls do their DB
        // work inside a Task).
        _ = AppDatabase.shared
        guard let recovery = AppDatabase.recovery else { return }

        let alert = NSAlert()
        alert.messageText = t("db.recovered.title")
        switch recovery {
        case .replacedUnopenableFile(let backupPath):
            alert.informativeText = t("db.recovered.replaced", ["path": backupPath])
        case .inMemoryFallback:
            alert.informativeText = t("db.recovered.inMemory")
        }
        alert.runModal()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    /// Without this, quitting (Cmd+Q or a kill) mid-download leaves the
    /// yt-dlp/ffmpeg child process orphaned, still writing into the temp dir
    /// indefinitely. `.terminateLater` holds the quit until `terminateAll()`
    /// finishes, then replies to let AppKit actually terminate.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        Task {
            await AppServices.downloadManager.terminateAll()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        WindowPresenter.showMainWindow()
        // Reopen is already fully handled above (existing window is unhidden and
        // brought to front) - returning true here would also let AppKit run its
        // own default reopen handling, which for a SwiftUI WindowGroup means
        // instantiating a brand-new window since hasVisibleWindows is false
        // (the window was only orderOut'd, not closed). That produced a
        // duplicate window on every Dock-icon reopen.
        return false
    }
}
