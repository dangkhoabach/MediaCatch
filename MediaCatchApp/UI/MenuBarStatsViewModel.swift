import MediaCatchCore
import Observation

/// Backs the menu bar's "Downloads: N" row — reads the active-download count
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
        activeDownloadCount = (try? repo.list().filter { $0.status == .downloading }.count) ?? 0
    }
}
