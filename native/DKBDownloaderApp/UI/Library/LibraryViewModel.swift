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

    func refresh() {
        guard let all = try? AppServices.downloadRepo.list() else { return }
        records = all.filter { $0.status != .downloading }
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
            errorMessage = "\(error)"
        }
    }

    func open(_ path: String) {
        if !NSWorkspace.shared.open(URL(fileURLWithPath: path)) {
            errorMessage = "Couldn't open \(path)"
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
