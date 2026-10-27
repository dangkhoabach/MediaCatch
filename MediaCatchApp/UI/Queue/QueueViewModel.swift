import MediaCatchCore
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

    /// Queued rows belong here too — they're accepted work waiting for a
    /// slot, not history — and they sort after the running ones so the list
    /// reads top-down as "in progress, then waiting".
    func refresh() {
        guard let all = try? AppServices.downloadRepo.list() else { return }
        let active = all.filter { $0.status == .downloading || $0.status == .queued }
        downloads = active.sorted { lhs, rhs in
            if (lhs.status == .queued) != (rhs.status == .queued) {
                return rhs.status == .queued
            }
            return (lhs.id ?? 0) < (rhs.id ?? 0)
        }

        // Forget the paused flag once a download leaves the queue, whatever
        // took it out (cancel, failure, a quit's reconcile). Pruning against
        // the active list rather than hooking each exit path means no new way
        // of finishing can leave an entry behind. Nothing user-visible hangs
        // on it — ids are AUTOINCREMENT, so a stale one can never attach
        // itself to a later download — but the set would otherwise only ever
        // grow for as long as the app runs.
        if !pausedIds.isEmpty {
            pausedIds.formIntersection(downloads.compactMap(\.id))
        }
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
