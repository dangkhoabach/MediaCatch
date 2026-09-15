import AppKit
import DKBDownloaderCore
import Observation

/// Ports `pages/Library.tsx`'s logic — both tabs (Downloads/Recent links).
@Observable
@MainActor
final class LibraryViewModel {
    enum Tab { case downloads, recent }

    var tab: Tab = .downloads {
        didSet { if tab == .recent { refreshRecent() } }
    }
    private(set) var records: [Download] = []
    private(set) var recentLinks: [UrlHistoryEntry] = []
    var recentSearch = ""
    var errorMessage: String?

    private var pollTask: Task<Void, Never>?

    var filteredRecent: [UrlHistoryEntry] {
        let query = recentSearch.trimmingCharacters(in: .whitespaces).lowercased()
        guard !query.isEmpty else { return recentLinks }
        return recentLinks.filter { ($0.title + $0.url).lowercased().contains(query) }
    }

    func start() {
        guard pollTask == nil else { return }
        pollTask = Task {
            while !Task.isCancelled {
                refresh()
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    /// Everything that isn't still active — a queued download hasn't happened
    /// yet, so it belongs in Queue rather than in history.
    func refresh() {
        guard let all = try? AppServices.downloadRepo.list() else { return }
        records = all.filter { $0.status != .downloading && $0.status != .queued }
    }

    func refreshRecent() {
        recentLinks = (try? AppServices.urlHistoryRepo.list()) ?? recentLinks
    }

    func delete(_ id: Int64, deleteFile: Bool) {
        do {
            if deleteFile, let path = try AppServices.downloadRepo.outputPath(id: id) {
                try? FileManager.default.removeItem(atPath: path)
            }
            try AppServices.downloadRepo.delete(id: id)
            refresh()
        } catch {
            errorMessage = "\(t("library.deleteError")): \(error)"
        }
    }

    /// Re-runs a download that failed or was cancelled, reusing the url,
    /// format selector and output folder already on the row.
    ///
    /// The rest of the options (output format, metadata embedding, cookies,
    /// aria2c) aren't stored per download, so this takes them from the current
    /// settings. That only differs from the original run if those settings
    /// changed since — with one narrow exception worth knowing about: an
    /// audio-only download retried this way doesn't get the remux-for-
    /// thumbnail-embedding treatment, because `audio_only` isn't recorded
    /// either. Storing it would need a schema change for a case this small.
    func retry(_ record: Download) {
        Task {
            let request = StartDownloadRequest(
                url: record.url,
                title: record.title,
                formatSelector: record.formatSelector,
                outputDir: record.outputDir,
                outputFormat: AppSettings.outputFormat(),
                embedMetadata: AppSettings.embedMetadata(),
                cookiesBrowser: AppSettings.cookiesBrowser(),
                useAria2c: AppSettings.useAria2c()
            )
            do {
                try await AppServices.downloadManager.start(request)
                AppNavigationState.shared.selectedSection = .queue
            } catch {
                errorMessage = "\(t("library.retryError")): \(error)"
            }
        }
    }

    func open(_ path: String) {
        if !NSWorkspace.shared.open(URL(fileURLWithPath: path)) {
            errorMessage = t("library.openError")
        }
    }

    func reveal(_ path: String) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    /// Mirrors `Library.tsx::handleRefetch` — hands off to Home via shared
    /// navigation state instead of a router push.
    func refetch(_ url: String) {
        AppNavigationState.shared.pendingFetchUrl = url
        AppNavigationState.shared.selectedSection = .home
    }

    func deleteRecent(_ id: Int64) {
        try? AppServices.urlHistoryRepo.delete(id: id)
        refreshRecent()
    }

    func clearRecent() {
        try? AppServices.urlHistoryRepo.clear()
        refreshRecent()
    }
}
