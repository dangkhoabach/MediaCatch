import MediaCatchCore
import Observation

/// Backs the menu bar icon and panel: the downloads in progress — reads the active-download count
/// straight from the shared DB (`DownloadRepository`) rather than
/// needing a live reference to whatever `DownloadManager` instance the app's
/// composition root ends up owning. Updated on a
/// `Task.sleep`-loop, the same burst-avoiding shape used by
/// `ChannelWatcher`/SignalBar's `MenuBarStatsViewModel`, instead of a fixed
/// `Timer`.
@Observable
@MainActor
public final class MenuBarStatsViewModel {
    public static let shared = MenuBarStatsViewModel()

    public private(set) var activeDownloadCount = 0
    /// Downloading first, then waiting for a slot, as the queue shows them.
    public private(set) var activeDownloads: [Download] = []
    private var loopTask: Task<Void, Never>?

    private init() {}

    public func start(interval: Duration = .seconds(3)) {
        guard loopTask == nil else { return }
        loopTask = Task { [weak self] in
            while let self, !Task.isCancelled {
                self.refresh()
                try? await Task.sleep(for: interval)
            }
        }
    }

    public func refresh() {
        let repo = DownloadRepository(dbQueue: AppDatabase.shared.dbQueue)
        let all = (try? repo.list()) ?? []
        activeDownloadCount = all.filter { $0.status == .downloading }.count
        let active = Self.active(in: all)
        if active != activeDownloads { activeDownloads = active }
    }

    /// What the menu bar panel lists: downloading, then queued.
    nonisolated static func active(in downloads: [Download]) -> [Download] {
        downloads.filter { $0.status == .downloading } + downloads.filter { $0.status == .queued }
    }
}
