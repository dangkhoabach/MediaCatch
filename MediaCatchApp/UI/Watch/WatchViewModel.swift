import MediaCatchCore
import Observation

/// Ports `pages/Watch.tsx`'s logic — `add()` mirrors
/// `watch.rs::add_watched_channel` exactly: dump the first 5 entries, mark
/// them all known *before* the first poll, so adding a channel never
/// bulk-downloads its back catalog.
@Observable
@MainActor
final class WatchViewModel {
    private(set) var channels: [WatchedChannel] = []
    var url = ""
    var adding = false
    var errorMessage: String?

    func refresh() {
        channels = (try? AppServices.watchedChannelRepo.list()) ?? channels
    }

    func add() async {
        let trimmed = url.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        guard isFetchableURL(trimmed) else {
            errorMessage = t("error.invalidUrl")
            return
        }
        adding = true
        defer { adding = false }

        do {
            let outputDir = AppSettings.ensureOutputDir()
            let outputFormat = AppSettings.outputFormat()
            let dump = try await AppServices.ytdlpClient.dumpPlaylist(url: trimmed, limit: 5)
            let title = dump.title ?? trimmed

            let channelId = try AppServices.watchedChannelRepo.insert(
                url: trimmed, title: title, outputDir: outputDir, outputFormat: outputFormat
            )
            for videoId in dump.entryIds {
                try? AppServices.watchedChannelRepo.markVideoKnown(channelId: channelId, videoId: videoId)
            }
            try? AppServices.watchedChannelRepo.touch(id: channelId)

            url = ""
            refresh()
        } catch {
            errorMessage = "\(t("watch.addError")): \(error)"
        }
    }

    func toggle(_ id: Int64, enabled: Bool) {
        if let index = channels.firstIndex(where: { $0.id == id }) {
            channels[index].enabled = enabled
        }
        do {
            try AppServices.watchedChannelRepo.setEnabled(id: id, enabled: enabled)
        } catch {
            errorMessage = "\(t("watch.toggleError")): \(error)"
            refresh()
        }
    }

    func remove(_ id: Int64) {
        do {
            try AppServices.watchedChannelRepo.remove(id: id)
            refresh()
        } catch {
            errorMessage = "\(t("watch.removeError")): \(error)"
        }
    }
}
