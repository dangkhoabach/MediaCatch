import Foundation

public struct StartDownloadRequest: Sendable {
    public var url: String
    public var title: String
    public var formatSelector: String
    public var outputDir: String
    public var outputFormat: String
    public var embedMetadata: Bool
    public var audioOnly: Bool
    public var cookiesBrowser: String?
    public var useAria2c: Bool

    public init(
        url: String, title: String, formatSelector: String, outputDir: String, outputFormat: String,
        embedMetadata: Bool = false, audioOnly: Bool = false, cookiesBrowser: String? = nil, useAria2c: Bool = false
    ) {
        self.url = url
        self.title = title
        self.formatSelector = formatSelector
        self.outputDir = outputDir
        self.outputFormat = outputFormat
        self.embedMetadata = embedMetadata
        self.audioOnly = audioOnly
        self.cookiesBrowser = cookiesBrowser
        self.useAria2c = useAria2c
    }
}

public enum DownloadEvent: Sendable, Equatable {
    case progress(downloadId: Int64, progress: DownloadProgress)
    case completed(downloadId: Int64, outputPath: String)
    case failed(downloadId: Int64, message: String)
    case canceled(downloadId: Int64)
}

/// Orchestrates yt-dlp downloads: builds the argument list for every option
/// combination, tracks one running `ProcessRunner` per download for pause/
/// resume/cancel, and moves the finished file out of a private temp
/// directory into the user's chosen output folder. Mirrors
/// `ytdlp.rs::start_download`/`cancel_download`/`pause_download`/
/// `resume_download`.
///
/// An `actor` (not App-layer-only, see D8's note re-evaluated in Phase 3):
/// nothing here needs AppKit — `Process`/`FileManager` are plain Foundation
/// — so it lives in Core, fully testable without a UI, with the real
/// sidecar binary paths injected by the caller (App layer resolves those
/// from the bundle, same division of responsibility as `ProcessRunner`'s
/// tests already use).
public actor DownloadManager {
    private let ytdlpURL: URL
    private let ffmpegURL: URL?
    private let downloadRepo: DownloadRepository
    private var runners: [Int64: ProcessRunner] = [:]
    private var canceledIds: Set<Int64> = []

    public nonisolated let events: AsyncStream<DownloadEvent>
    private let eventsContinuation: AsyncStream<DownloadEvent>.Continuation

    public init(ytdlpURL: URL, ffmpegURL: URL?, downloadRepo: DownloadRepository) {
        self.ytdlpURL = ytdlpURL
        self.ffmpegURL = ffmpegURL
        self.downloadRepo = downloadRepo
        var continuation: AsyncStream<DownloadEvent>.Continuation!
        self.events = AsyncStream { continuation = $0 }
        self.eventsContinuation = continuation
        try? downloadRepo.reconcileInterrupted()
    }

    @discardableResult
    public func start(_ request: StartDownloadRequest) throws -> Int64 {
        let downloadId = try downloadRepo.insert(
            url: request.url, title: request.title, formatSelector: request.formatSelector, outputDir: request.outputDir
        )

        let tempDir = Self.tempDownloadDir(downloadId: downloadId)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let args = Self.buildArguments(request: request, tempDir: tempDir, ffmpegURL: ffmpegURL)

        let runner = try ProcessRunner(executableURL: ytdlpURL, arguments: args)
        runners[downloadId] = runner

        Task { await self.observe(runner: runner, downloadId: downloadId, outputDir: request.outputDir) }
        return downloadId
    }

    public func cancel(downloadId: Int64) {
        canceledIds.insert(downloadId)
        runners[downloadId]?.terminate()
    }

    /// Terminates every in-flight yt-dlp/ffmpeg process without touching DB
    /// state — called from `applicationWillTerminate` so app quit doesn't
    /// leave orphaned child processes running in the background.
    public func terminateAll() {
        for runner in runners.values {
            runner.terminate()
        }
    }

    /// `SIGSTOP`/`SIGCONT` on the running process — see Phase 0's PoC.
    @discardableResult
    public func pause(downloadId: Int64) -> Bool {
        runners[downloadId]?.suspend() ?? false
    }

    @discardableResult
    public func resume(downloadId: Int64) -> Bool {
        runners[downloadId]?.resume() ?? false
    }

    private func observe(runner: ProcessRunner, downloadId: Int64, outputDir: String) async {
        var finalPath: String?
        var lastErrorLine: String?
        var exitCode: Int32 = 0

        for await event in runner.events {
            switch event {
            case .stdoutLine(let line):
                if let progress = parseDownloadProgressLine(line) {
                    eventsContinuation.yield(.progress(downloadId: downloadId, progress: progress))
                } else if !line.isEmpty {
                    // With --quiet --no-warnings, the only other stdout line
                    // is the --print after_move:filepath output.
                    finalPath = line
                }
            case .stderrLine(let line):
                if !line.isEmpty { lastErrorLine = line }
            case .terminated(let code):
                exitCode = code
            }
        }

        finish(downloadId: downloadId, exitCode: exitCode, finalPath: finalPath, errorMessage: lastErrorLine, outputDir: outputDir)
    }

    /// `cancel_download` already marks the row "canceled" and removed the
    /// runner synchronously before calling `terminate()` — but the process's
    /// own `terminated` event still arrives afterwards regardless (killing
    /// it triggers one too), so this must check `canceledIds` first and
    /// never let a killed-on-purpose process get treated as an error. Same
    /// pattern proven in Phase 0's `externalCancelFlagDistinguishesUserCancelFromRealFailure`.
    private func finish(downloadId: Int64, exitCode: Int32, finalPath: String?, errorMessage: String?, outputDir: String) {
        runners[downloadId] = nil
        let tempDir = Self.tempDownloadDir(downloadId: downloadId)

        if canceledIds.remove(downloadId) != nil {
            try? downloadRepo.setStatus(id: downloadId, status: .canceled)
            try? FileManager.default.removeItem(at: tempDir)
            eventsContinuation.yield(.canceled(downloadId: downloadId))
            return
        }

        guard exitCode == 0, let finalPath, let movedPath = Self.moveToOutputDir(tempPath: finalPath, outputDir: outputDir) else {
            let message = errorMessage ?? "Couldn't move the finished file to the output folder"
            try? downloadRepo.setStatus(id: downloadId, status: .error, errorMessage: message)
            try? FileManager.default.removeItem(at: tempDir)
            eventsContinuation.yield(.failed(downloadId: downloadId, message: message))
            return
        }

        try? downloadRepo.setStatus(id: downloadId, status: .completed)
        try? downloadRepo.setOutputPath(id: downloadId, outputPath: movedPath)
        try? FileManager.default.removeItem(at: tempDir)
        eventsContinuation.yield(.completed(downloadId: downloadId, outputPath: movedPath))
    }

    // MARK: - Pure helpers (unit-tested without spawning any process)

    /// Where a download's working directory lives while yt-dlp downloads and
    /// post-processes it — kept out of the user's chosen output folder so a
    /// crash, cancel, or leftover post-processing artifact never lands
    /// there. Pure function of `downloadId`, matching `ytdlp.rs::temp_download_dir`.
    static func tempDownloadDir(downloadId: Int64) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("dkb-downloader", isDirectory: true)
            .appendingPathComponent(String(downloadId), isDirectory: true)
    }

    /// Appends " (1)", " (2)", … before the extension until the name is free.
    /// `moveItem`/`copyItem` both fail outright against an existing
    /// destination, so without this, re-downloading a video whose file is
    /// already in the output folder reported an error and deleted the
    /// finished file along with its temp dir.
    static func uniqueDestination(filename: String, outputDir: String) -> URL {
        let directory = URL(fileURLWithPath: outputDir)
        let base = (filename as NSString).deletingPathExtension
        let ext = (filename as NSString).pathExtension
        var candidate = directory.appendingPathComponent(filename)
        var counter = 1
        while FileManager.default.fileExists(atPath: candidate.path) {
            let numbered = ext.isEmpty ? "\(base) (\(counter))" : "\(base) (\(counter)).\(ext)"
            candidate = directory.appendingPathComponent(numbered)
            counter += 1
        }
        return candidate
    }

    /// Moves the finished file out of its temp working directory into the
    /// user's chosen output folder. Falls back to copy+delete when the
    /// rename fails across filesystem boundaries.
    static func moveToOutputDir(tempPath: String, outputDir: String) -> String? {
        let tempURL = URL(fileURLWithPath: tempPath)
        let destURL = uniqueDestination(filename: tempURL.lastPathComponent, outputDir: outputDir)
        do {
            try FileManager.default.moveItem(at: tempURL, to: destURL)
            return destURL.path
        } catch {
            do {
                try FileManager.default.copyItem(at: tempURL, to: destURL)
                try? FileManager.default.removeItem(at: tempURL)
                return destURL.path
            } catch {
                return nil
            }
        }
    }

    /// Builds the exact yt-dlp argument list for one download — pure and
    /// order-preserving so it can be unit-tested for every option
    /// combination without spawning anything. Mirrors
    /// `ytdlp.rs::start_download`'s argument construction flag-for-flag.
    static func buildArguments(request: StartDownloadRequest, tempDir: URL, ffmpegURL: URL?) -> [String] {
        var args: [String] = [
            "-f", request.formatSelector,
            "--merge-output-format", request.outputFormat,
            "-o", tempDir.appendingPathComponent("%(title)s.%(ext)s").path,
            "--quiet",
            "--no-warnings",
            // start_download always targets exactly one video — a
            // `watch?v=X&list=Y` URL would otherwise download the entire
            // playlist Y. Bulk playlist downloads go through
            // expandPlaylist + batch mode instead.
            "--no-playlist",
            // Forces the progress bar even though stdout is a pipe, not a
            // tty — yt-dlp otherwise silently skips all progress output,
            // confirmed empirically in Phase 0.
            "--progress",
            "--newline",
            "--progress-template", "download:DKB|%(progress._percent_str)s|%(progress._speed_str)s|%(progress._eta_str)s",
            "--print", "after_move:filepath",
        ]

        if let ffmpegURL {
            args.append("--ffmpeg-location")
            args.append(ffmpegURL.path)
        }

        if request.embedMetadata {
            args.append("--embed-thumbnail")
            args.append("--embed-chapters")
            args.append("--embed-metadata")
            // Thumbnail embedding only supports a fixed list of containers
            // — audio-only formats commonly download as webm/opus, which
            // isn't on that list. --audio-format best remuxes (no
            // re-encode) into the correct container for whatever codec was
            // downloaded, so embedding succeeds.
            if request.audioOnly {
                args.append("-x")
                args.append("--audio-format")
                args.append("best")
            }
            args.append("--sub-langs")
            args.append("en,vi")
            args.append("--embed-subs")
        }

        YtdlpClient.appendCookiesArg(&args, request.cookiesBrowser)

        if request.useAria2c {
            args.append("--external-downloader")
            args.append("aria2c")
            args.append("--external-downloader-args")
            args.append("aria2c:-x16 -s16 -k1M")
        }

        args.append(request.url)
        return args
    }
}
