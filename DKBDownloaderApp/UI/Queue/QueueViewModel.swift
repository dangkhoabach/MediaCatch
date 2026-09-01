import DKBDownloaderCore
import Observation

/// Ports `pages/Queue.tsx`'s logic — polls the DB for the "downloading" list
/// (same interval-loop shape as `MenuBarStatsViewModel`/`ChannelWatcher`)
/// instead of listening for a `download-complete`/`download-error` Tauri
/// event, since there's no cross-process boundary to bridge anymore; live
/// per-download progress comes from `DownloadEventCenter` instead, the
/// single subscriber of `DownloadManager`'s event stream.
@Observable
@MainActor
final class QueueViewModel {
    private(set) var downloads: [Download] = []
    private var pausedIds: Set<Int64> = []
    private var pollTask: Task<Void, Never>?

    func isPaused(_ id: Int64) -> Bool {
        pausedIds.contains(id)
    }

    func start() {
        guard pollTask == nil else { return }
        pollTask = Task {
            while !Task.isCancelled {
                refresh()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    func refresh() {
        guard let all = try? AppServices.downloadRepo.list() else { return }
        downloads = all.filter { $0.status == .downloading }
    }

    func togglePause(_ id: Int64) async {
        if pausedIds.contains(id) {
            await AppServices.downloadManager.resume(downloadId: id)
            pausedIds.remove(id)
        } else {
            await AppServices.downloadManager.pause(downloadId: id)
            pausedIds.insert(id)
        }
    }

    func cancel(_ id: Int64) async {
        await AppServices.downloadManager.cancel(downloadId: id)
        refresh()
    }
}
