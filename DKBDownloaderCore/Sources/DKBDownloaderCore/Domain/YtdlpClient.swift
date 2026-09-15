import Foundation

/// One run of yt-dlp: what it printed, and what it complained about on the way.
struct RunOutput: Sendable {
    let stdout: String
    let warnings: [String]
}

/// A successful metadata fetch. Warnings live beside `info` rather than inside
/// it because they describe how the extraction went, not the video itself.
public struct VideoInfoFetch: Sendable {
    public let info: VideoInfo
    /// yt-dlp's `WARNING:` lines, de-duplicated with the prefix stripped.
    /// Empty on a clean fetch.
    public let warnings: [String]
}

public enum YtdlpError: Error, Equatable, Sendable {
    case processFailed(String)
    /// The process was still running when its time limit ran out and was
    /// killed. Distinct from `processFailed` because there's no stderr worth
    /// showing — a stalled network read produces no output at all.
    case timedOut
}

/// Wraps the yt-dlp binary for the "run to completion and parse JSON"
/// operations — mirrors `ytdlp.rs`'s `fetch_video_info`/`dump_playlist`/
/// `expand_playlist`. Long-running downloads with a live progress stream are
/// `DownloadManager`'s job, not this type's.
public struct YtdlpClient: Sendable {
    let ytdlpURL: URL

    public init(ytdlpURL: URL) {
        self.ytdlpURL = ytdlpURL
    }

    /// Note the absent `--no-warnings`: warnings are the point here. yt-dlp
    /// announces a degraded extraction that way — "some formats may be
    /// missing" — and suppressing them is how a site change turns into an app
    /// that quietly stops offering 1080p with nothing to explain it. They go
    /// to stderr, so the JSON on stdout is unaffected.
    public func fetchVideoInfo(
        url: String, cookiesBrowser: String? = nil, cookiesFile: String? = nil
    ) async throws -> VideoInfoFetch {
        var args = ["-j", "--no-playlist"]
        Self.appendCookiesArg(&args, browser: cookiesBrowser, file: cookiesFile)
        // See `DownloadManager.buildArguments` — `--` keeps a dash-leading
        // string from being parsed as an option instead of a URL.
        args.append("--")
        args.append(url)

        let output = try await Self.run(ytdlpURL, args)
        let info = try JSONDecoder().decode(YtDlpInfo.self, from: Data(output.stdout.utf8))
        return VideoInfoFetch(info: VideoInfo(info), warnings: output.warnings)
    }

    /// `--flat-playlist` only resolves cheap per-entry fields (id/title/url),
    /// not full metadata for every video. `limit` caps how many entries come
    /// back (used by channel polling); `nil` fetches the entire playlist.
    public func dumpPlaylist(url: String, limit: Int? = nil) async throws -> YtDlpPlaylistDump {
        var args = ["-J", "--flat-playlist", "--no-warnings"]
        if let limit {
            args.append("--playlist-end")
            args.append(String(limit))
        }
        args.append("--")
        args.append(url)

        let output = try await Self.run(ytdlpURL, args)
        return try JSONDecoder().decode(YtDlpPlaylistDump.self, from: Data(output.stdout.utf8))
    }

    public func expandPlaylist(url: String) async throws -> [PlaylistEntry] {
        try await dumpPlaylist(url: url, limit: nil).asPlaylistEntries()
    }

    /// Supplies cookies either from an exported Netscape-format file or
    /// straight from an installed browser's own store — shared by
    /// `fetchVideoInfo` and `DownloadManager` so both authenticate the same
    /// way. yt-dlp rejects being given both, so the explicit file wins: it's
    /// the one the user had to go out of their way to pick.
    static func appendCookiesArg(_ args: inout [String], browser: String?, file: String? = nil) {
        if let file, !file.isEmpty {
            args.append("--cookies")
            args.append(file)
            return
        }
        if let browser, !browser.isEmpty {
            args.append("--cookies-from-browser")
            args.append(browser)
        }
    }

    /// Long enough that a slow-but-working extraction (a large playlist, a
    /// site that takes its time) still finishes, short enough that a stalled
    /// connection doesn't leave the UI spinning forever.
    static let defaultTimeout: Duration = .seconds(90)

    /// Runs `executable` to completion and returns its stdout plus whatever it
    /// warned about, throwing the trimmed stderr as a plain error message on
    /// non-zero exit — mirrors `fetch_video_info`/`dump_playlist`'s error
    /// handling in ytdlp.rs.
    ///
    /// Kills the process and throws `.timedOut` if it outlives `timeout`, and
    /// kills it too if the calling task is cancelled — without that, a
    /// cancelled fetch would leave yt-dlp running to completion in the
    /// background with nobody left to read its output.
    static func run(_ executable: URL, _ args: [String], timeout: Duration = defaultTimeout) async throws -> RunOutput {
        enum Outcome: Sendable {
            // stderr is kept as lines, not one accumulated string:
            // `ProcessRunner` strips each line's newline, so appending them
            // together would run separate messages into one unsplittable blob.
            case finished(stdout: String, stderrLines: [String], exitCode: Int32)
            case timedOut
        }

        let runner = try ProcessRunner(executableURL: executable, arguments: args)

        let outcome = await withTaskCancellationHandler {
            await withTaskGroup(of: Outcome.self) { group in
                group.addTask {
                    var stdout = ""
                    var stderrLines: [String] = []
                    var exitCode: Int32 = 0
                    for await event in runner.events {
                        switch event {
                        case .stdoutLine(let line): stdout += line
                        case .stderrLine(let line): stderrLines.append(line)
                        case .terminated(let code): exitCode = code
                        }
                    }
                    return .finished(stdout: stdout, stderrLines: stderrLines, exitCode: exitCode)
                }
                group.addTask {
                    try? await Task.sleep(for: timeout)
                    // Cancelled means the drain above already won; the
                    // process is gone and there's nothing to kill.
                    guard !Task.isCancelled else { return .timedOut }
                    // Terminating here, rather than after the group returns,
                    // is what lets the draining child finish: a task group
                    // waits for every child before it returns, so leaving the
                    // process alive would hang this call instead of timing
                    // it out.
                    runner.terminate()
                    return .timedOut
                }

                let first = await group.next() ?? .timedOut
                group.cancelAll()
                return first
            }
        } onCancel: {
            runner.terminate()
        }

        switch outcome {
        case .timedOut:
            throw YtdlpError.timedOut
        case .finished(let stdout, let stderrLines, let exitCode):
            guard exitCode == 0 else {
                throw YtdlpError.processFailed(Self.failureMessage(from: stderrLines))
            }
            return RunOutput(stdout: stdout, warnings: Self.parseWarnings(stderrLines))
        }
    }

    /// What actually went wrong, without the warnings that happened to precede
    /// it. yt-dlp prints warnings and errors down the same stream, so keeping
    /// everything would bury a one-line failure under an unrelated notice —
    /// the deprecation warning YouTube extraction currently emits on every
    /// single call, for instance. Falls back to the whole thing when nothing
    /// looks like an error, so a failure never reports an empty reason.
    static func failureMessage(from stderrLines: [String]) -> String {
        let nonWarning = stderrLines.filter {
            !$0.trimmingCharacters(in: .whitespaces).hasPrefix("WARNING:")
        }
        let chosen = nonWarning.contains { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            ? nonWarning
            : stderrLines
        return chosen.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// yt-dlp's own `WARNING:` lines, prefix stripped and de-duplicated in the
    /// order they first appeared. Everything else on stderr is progress noise
    /// that means nothing to a user on a successful run.
    static func parseWarnings(_ stderrLines: [String]) -> [String] {
        var seen = Set<String>()
        return stderrLines.compactMap { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("WARNING:") else { return nil }
            let body = trimmed.dropFirst("WARNING:".count).trimmingCharacters(in: .whitespaces)
            guard !body.isEmpty, seen.insert(body).inserted else { return nil }
            return body
        }
    }
}
