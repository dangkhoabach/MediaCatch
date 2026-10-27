import MediaCatchCore

/// Starts everything that has to run for the lifetime of the app and wires
/// notification routing — the composition-root work that waited
/// for real destinations (Queue/Library) to exist. Called once
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
            guard let newVersion = try? await AppServices.ytdlpUpdater.updateIfNeeded(),
                  AppSettings.notificationsEnabled() else { return }
            await NotificationManager.shared.notify(
                title: t("notification.ytdlpUpdated.title"),
                body: t("notification.ytdlpUpdated.body", ["version": newVersion]),
                route: nil
            )
        }
    }
}
