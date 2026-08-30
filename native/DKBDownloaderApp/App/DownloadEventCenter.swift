import DKBDownloaderCore
import Observation

/// The one and only subscriber of `AppServices.downloadManager.events` for
/// the whole app. `AsyncStream` delivers each event to exactly one iterator
/// — if Queue and Library each ran their own `for await event in
/// downloadManager.events` loop, they'd silently split the events between
/// them instead of both seeing everything. This re-broadcasts live progress
/// via an `@Observable` property any number of views can read, and every
/// other Phase 9 piece (Library's list refresh, notifications) reacts to the
/// same single stream through this instead of subscribing again.
@Observable
@MainActor
final class DownloadEventCenter {
    static let shared = DownloadEventCenter()

    private(set) var progressById: [Int64: DownloadProgress] = [:]
    /// Bumped on every terminal event (completed/failed/canceled) so
    /// Queue/Library can react without polling the stream themselves.
    private(set) var changeTick = 0

    private var started = false

    private init() {}

    func start() {
        guard !started else { return }
        started = true
        Task {
            for await event in AppServices.downloadManager.events {
                handle(event)
            }
        }
    }

    private func handle(_ event: DownloadEvent) {
        switch event {
        case .progress(let downloadId, let progress):
            progressById[downloadId] = progress
        case .completed(let downloadId, _):
            progressById[downloadId] = nil
            changeTick += 1
            notifyIfEnabled(titlePrefix: "Download complete", downloadId: downloadId, route: "library")
        case .failed(let downloadId, _):
            progressById[downloadId] = nil
            changeTick += 1
            notifyIfEnabled(titlePrefix: "Download failed", downloadId: downloadId, route: "library")
        case .canceled(let downloadId):
            progressById[downloadId] = nil
            changeTick += 1
        }
    }

    /// Mirrors `App.tsx::DownloadNotifications` — body is the download's own
    /// title (looked up fresh from the DB), same for both outcomes; only the
    /// notification's title differs.
    private func notifyIfEnabled(titlePrefix: String, downloadId: Int64, route: String) {
        guard AppSettings.notificationsEnabled() else { return }
        let downloads = (try? AppServices.downloadRepo.list()) ?? []
        let title = downloads.first { $0.id == downloadId }?.title ?? ""
        Task {
            await NotificationManager.shared.notify(title: titlePrefix, body: title, route: route)
        }
    }
}
