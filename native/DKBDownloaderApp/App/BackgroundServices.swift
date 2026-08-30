import DKBDownloaderCore

/// Starts everything that has to run for the lifetime of the app and wires
/// notification routing — the composition-root work Phase 5/8 deliberately
/// deferred until real destinations (Queue/Library) existed. Called once
/// from `AppDelegate.applicationDidFinishLaunching`.
enum BackgroundServices {
    @MainActor
    static func start() {
        DownloadEventCenter.shared.start()

        Task { await AppServices.channelWatcher.start() }
        Task {
            for await event in AppServices.channelWatcher.events {
                switch event {
                case .newVideoDownloading(let channelTitle, let videoTitle, _):
                    guard AppSettings.notificationsEnabled() else { continue }
                    await NotificationManager.shared.notify(
                        title: t("notification.watchedNewVideo.title", ["channel": channelTitle]),
                        body: videoTitle, route: "queue"
                    )
                }
            }
        }

        NotificationManager.shared.onRouteSelected = { route in
            switch route {
            case "queue": AppNavigationState.shared.selectedSection = .queue
            case "library": AppNavigationState.shared.selectedSection = .library
            default: break
            }
        }

        // Checks for a newer yt-dlp release once per launch, independent of
        // this app's own release cycle — mirrors `ytdlp.rs::update_ytdlp`'s
        // call site in `App.tsx::YtdlpUpdateChecker`.
        Task {
            let updater = YtdlpUpdater(ytdlpURL: AppServices.ytdlpURL, binDirectory: AppDatabaseLocation.binDirectory())
            guard let newVersion = try? await updater.updateIfNeeded(), AppSettings.notificationsEnabled() else { return }
            await NotificationManager.shared.notify(
                title: t("notification.ytdlpUpdated.title"),
                body: t("notification.ytdlpUpdated.body", ["version": newVersion]),
                route: nil
            )
        }
    }
}
