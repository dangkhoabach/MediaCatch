import DKBDownloaderCore
import Foundation
import Observation

struct BatchItem: Identifiable {
    enum Status { case pending, working, done, error }

    let id = UUID()
    var url: String
    var status: Status = .pending
    var message: String?
}

/// Ports `home-state.tsx` + `pages/Home.tsx`'s logic 1:1 onto
/// `AppServices.ytdlpClient`/`downloadManager` — same field names/flow, no
/// React/Tauri IPC in between since both now live in the same process.
@Observable
@MainActor
final class HomeViewModel {
    var url = ""
    var loading = false
    var info: VideoInfo?
    /// The URL `info`/`selectedFormatId` actually describe — not necessarily
    /// what's in the text field by the time Download is pressed, since the
    /// user can keep editing it after a fetch. Downloading the typed URL with
    /// the previous video's format id would fetch the wrong video (or fail on
    /// a format id that doesn't exist there).
    private var fetchedUrl: String?
    var platform: String?
    var selectedFormatId: String?
    var audioOnly = false
    var starting = false
    var errorMessage: String?

    var batchMode = false
    var batchText = ""
    var batchItems: [BatchItem] = []
    var batchRunning = false

    private let ytdlpClient = AppServices.ytdlpClient
    private let downloadManager = AppServices.downloadManager
    private let urlHistoryRepo = AppServices.urlHistoryRepo

    /// Owned here rather than spawned ad-hoc at each call site so the UI has
    /// something to cancel. Cancelling it kills the yt-dlp process too, not
    /// just the Swift task — see `YtdlpClient.run`.
    private var fetchTask: Task<Void, Never>?

    /// Only recognizes unambiguous, YouTube-only playlist links (a bare
    /// `/playlist?list=...` or `list=` without an accompanying `v=`) —
    /// mirrors `Home.tsx::isPlaylistUrl` exactly, including its reasoning: a
    /// `watch?v=X&list=Y` link's intent is almost always "this one video".
    private func isPlaylistUrl(_ rawUrl: String) -> Bool {
        guard let components = URLComponents(string: rawUrl), let host = components.host?.lowercased() else {
            return false
        }
        guard host == "youtube.com" || host.hasSuffix(".youtube.com") else { return false }
        let items = components.queryItems ?? []
        let hasList = items.contains { $0.name == "list" }
        let hasV = items.contains { $0.name == "v" }
        return hasList && !hasV
    }

    private static let platformPatterns: [(suffixes: [String], label: String)] = [
        (["youtube.com", "youtu.be"], "YouTube"),
        (["facebook.com", "fb.watch"], "Facebook"),
        (["instagram.com"], "Instagram"),
        (["tiktok.com"], "TikTok"),
        (["twitter.com", "x.com"], "Twitter/X"),
    ]

    /// yt-dlp already handles extraction for all of these — this is purely a
    /// UI label, no backend difference. Mirrors `Home.tsx::detectPlatform`.
    private func detectPlatform(_ rawUrl: String) -> String? {
        guard let host = URLComponents(string: rawUrl)?.host?.lowercased() else { return nil }
        for (suffixes, label) in Self.platformPatterns {
            if suffixes.contains(where: { host == $0 || host.hasSuffix(".\($0)") }) { return label }
        }
        return nil
    }

    /// Entry point for every "go fetch this" action in the UI. Replaces any
    /// fetch already in flight, so a second Fetch press doesn't leave the
    /// first yt-dlp process running unattended.
    func startFetch(overrideUrl: String? = nil) {
        fetchTask?.cancel()
        fetchTask = Task { [weak self] in
            await self?.fetchInfo(overrideUrl: overrideUrl)
        }
    }

    /// Cancelling the task terminates the child process; `fetchInfo`'s own
    /// `defer` clears `loading` on the way out.
    func cancelFetch() {
        fetchTask?.cancel()
        fetchTask = nil
    }

    func fetchInfo(overrideUrl: String? = nil) async {
        let trimmed = (overrideUrl ?? url).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard isFetchableURL(trimmed) else {
            errorMessage = t("error.invalidUrl")
            return
        }
        errorMessage = nil

        if isPlaylistUrl(trimmed) {
            await expandPlaylist(trimmed)
            return
        }

        loading = true
        info = nil
        fetchedUrl = nil
        platform = detectPlatform(trimmed)
        selectedFormatId = nil
        defer { loading = false }

        do {
            let result = try await ytdlpClient.fetchVideoInfo(url: trimmed, cookiesBrowser: AppSettings.cookiesBrowser())
            info = result
            fetchedUrl = trimmed
            try? urlHistoryRepo.upsert(url: trimmed, title: result.title)
            selectedFormatId = defaultFormatId(for: result, audioOnly: audioOnly)
        } catch {
            // A cancelled fetch surfaces as the killed process's non-zero
            // exit; that's the user's own doing, not something to report.
            guard !Task.isCancelled else { return }
            errorMessage = errorText(for: error, fallbackKey: "home.fetchError")
        }
    }

    /// Timeouts get their own message: the underlying error carries no stderr
    /// to show (a stalled connection prints nothing), so the generic
    /// "couldn't fetch: <error>" form would read as an empty failure.
    private func errorText(for error: Error, fallbackKey: String) -> String {
        if case YtdlpError.timedOut = error {
            return t("home.fetchTimeout")
        }
        return "\(t(fallbackKey)): \(error)"
    }

    private func expandPlaylist(_ playlistUrl: String) async {
        loading = true
        defer { loading = false }
        do {
            let entries = try await ytdlpClient.expandPlaylist(url: playlistUrl)
            guard !entries.isEmpty else {
                errorMessage = t("home.playlistEmpty")
                return
            }
            batchMode = true
            batchItems = []
            batchText = entries.map(\.url).joined(separator: "\n")
        } catch {
            guard !Task.isCancelled else { return }
            errorMessage = errorText(for: error, fallbackKey: "home.playlistExpandError")
        }
    }

    private func defaultFormatId(for info: VideoInfo, audioOnly: Bool) -> String? {
        if audioOnly {
            return info.formats
                .filter { $0.hasAudio && !$0.hasVideo }
                .max { ($0.tbr ?? 0) < ($1.tbr ?? 0) }?
                .formatId
        }
        let bestVideo = info.formats
            .filter(\.hasVideo)
            .max { ($0.height ?? 0) < ($1.height ?? 0) }
        let bestImage = info.formats
            .filter { !$0.hasVideo && !$0.hasAudio }
            .max { ($0.filesize ?? 0) < ($1.filesize ?? 0) }
        return bestVideo?.formatId ?? bestImage?.formatId
    }

    func setAudioOnly(_ enabled: Bool) {
        audioOnly = enabled
        guard let info else { return }
        selectedFormatId = defaultFormatId(for: info, audioOnly: enabled)
    }

    func download() async {
        guard let info, let fetchedUrl else { return }
        errorMessage = nil
        starting = true
        defer { starting = false }

        guard let format = info.formats.first(where: { $0.formatId == selectedFormatId }) else {
            errorMessage = t("home.noFormatSelected")
            return
        }

        // A format with no video track is already a complete standalone
        // asset on its own — an audio-only track, or (neither video nor
        // audio) a photo post — no audio to merge in either way.
        let selector: String
        if !format.hasVideo {
            selector = format.formatId
        } else if format.hasAudio {
            selector = format.formatId
        } else {
            selector = "\(format.formatId)+bestaudio/best"
        }

        let request = StartDownloadRequest(
            url: fetchedUrl,
            title: info.title,
            formatSelector: selector,
            outputDir: AppSettings.ensureOutputDir(),
            outputFormat: AppSettings.outputFormat(),
            embedMetadata: AppSettings.embedMetadata(),
            audioOnly: !format.hasVideo && format.hasAudio,
            cookiesBrowser: AppSettings.cookiesBrowser(),
            useAria2c: AppSettings.useAria2c()
        )

        do {
            try await downloadManager.start(request)
            AppNavigationState.shared.selectedSection = .queue
        } catch {
            errorMessage = "\(t("home.downloadStartError")): \(error)"
        }
    }

    /// How many metadata fetches run at once in batch mode. Each one is a
    /// yt-dlp process doing its own network round-trip (~10s against YouTube
    /// here), so fetching them one after another made a 20-link batch take
    /// minutes. 4 keeps the wall-clock down without firing a whole batch at
    /// the site at once.
    private static let maxConcurrentBatchFetches = 4

    func submitBatch() async {
        var seen = Set<String>()
        let urls = batchText
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
        guard !urls.isEmpty else { return }

        batchRunning = true
        batchItems = urls.map { BatchItem(url: $0) }
        defer { batchRunning = false }

        let outputDir = AppSettings.ensureOutputDir()
        let outputFormat = AppSettings.outputFormat()
        let embedMetadata = AppSettings.embedMetadata()
        let cookiesBrowser = AppSettings.cookiesBrowser()
        let useAria2c = AppSettings.useAria2c()

        for index in urls.indices where !isFetchableURL(urls[index]) {
            batchItems[index].status = .error
            batchItems[index].message = t("error.invalidUrl")
        }
        let pending = urls.indices.filter { isFetchableURL(urls[$0]) }

        // Captured locally so the task-group children don't touch this
        // (main-actor-isolated) view model; `YtdlpClient` is a Sendable value.
        let client = ytdlpClient
        var cursor = 0
        while cursor < pending.count {
            let chunk = Array(pending[cursor..<min(cursor + Self.maxConcurrentBatchFetches, pending.count)])
            cursor += chunk.count

            for index in chunk { batchItems[index].status = .working }

            let fetched = await withTaskGroup(of: (Int, VideoInfo?, String?).self) { group in
                for index in chunk {
                    let itemUrl = urls[index]
                    group.addTask {
                        do {
                            let info = try await client.fetchVideoInfo(url: itemUrl, cookiesBrowser: cookiesBrowser)
                            return (index, info, nil)
                        } catch {
                            return (index, nil, "\(error)")
                        }
                    }
                }
                var results: [(Int, VideoInfo?, String?)] = []
                for await result in group { results.append(result) }
                // Results arrive in completion order; queue the downloads in
                // the order the user typed them instead.
                return results.sorted { $0.0 < $1.0 }
            }

            for (index, info, fetchError) in fetched {
                let itemUrl = urls[index]
                guard let info else {
                    batchItems[index].status = .error
                    batchItems[index].message = fetchError
                    continue
                }
                try? urlHistoryRepo.upsert(url: itemUrl, title: info.title)
                do {
                    let selector: String
                    if audioOnly {
                        selector = "bestaudio/best"
                    } else {
                        guard let best = info.formats.filter(\.hasVideo).max(by: { ($0.height ?? 0) < ($1.height ?? 0) }) else {
                            throw YtdlpError.processFailed(t("home.noFormatSelected"))
                        }
                        selector = best.hasAudio ? best.formatId : "\(best.formatId)+bestaudio/best"
                    }

                    let request = StartDownloadRequest(
                        url: itemUrl, title: info.title, formatSelector: selector,
                        outputDir: outputDir, outputFormat: outputFormat,
                        embedMetadata: embedMetadata, audioOnly: audioOnly,
                        cookiesBrowser: cookiesBrowser, useAria2c: useAria2c
                    )
                    try await downloadManager.start(request)
                    batchItems[index].status = .done
                    batchItems[index].message = info.title
                } catch {
                    batchItems[index].status = .error
                    batchItems[index].message = "\(error)"
                }
            }
        }
    }

    /// Mirrors `Home.tsx`'s `useEffect` on `pendingFetchUrl` — called from
    /// the view whenever `AppNavigationState.shared.pendingFetchUrl` changes.
    func handlePendingFetch(_ pendingUrl: String) {
        batchMode = false
        url = pendingUrl
        startFetch(overrideUrl: pendingUrl)
        AppNavigationState.shared.pendingFetchUrl = nil
    }
}
