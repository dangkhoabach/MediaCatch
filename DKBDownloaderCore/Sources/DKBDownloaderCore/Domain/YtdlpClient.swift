import Foundation

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

    public func fetchVideoInfo(url: String, cookiesBrowser: String? = nil, cookiesFile: String? = nil) async throws -> VideoInfo {
        var args = ["-j", "--no-playlist", "--no-warnings"]
        Self.appendCookiesArg(&args, browser: cookiesBrowser, file: cookiesFile)
        // See `DownloadManager.buildArguments` — `--` keeps a dash-leading
        // string from being parsed as an option instead of a URL.
        args.append("--")
        args.append(url)

        let output = try await Self.run(ytdlpURL, args)
        let info = try JSONDecoder().decode(YtDlpInfo.self, from: Data(output.utf8))
        return VideoInfo(info)
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
        return try JSONDecoder().decode(YtDlpPlaylistDump.self, from: Data(output.utf8))
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

    /// Runs `executable` to completion and returns its stdout, throwing the
    /// trimmed stderr as a plain error message on non-zero exit — mirrors
    /// `fetch_video_info`/`dump_playlist`'s error handling in ytdlp.rs.
    ///
    /// Kills the process and throws `.timedOut` if it outlives `timeout`, and
    /// kills it too if the calling task is cancelled — without that, a
    /// cancelled fetch would leave yt-dlp running to completion in the
    /// background with nobody left to read its output.
    static func run(_ executable: URL, _ args: [String], timeout: Duration = defaultTimeout) async throws -> String {
        enum Outcome: Sendable {
            case finished(stdout: String, stderr: String, exitCode: Int32)
            case timedOut
        }

        let runner = try ProcessRunner(executableURL: executable, arguments: args)

        let outcome = await withTaskCancellationHandler {
            await withTaskGroup(of: Outcome.self) { group in
                group.addTask {
                    var stdout = ""
                    var stderr = ""
                    var exitCode: Int32 = 0
                    for await event in runner.events {
                        switch event {
                        case .stdoutLine(let line): stdout += line
                        case .stderrLine(let line): stderr += line
                        case .terminated(let code): exitCode = code
                        }
                    }
                    return .finished(stdout: stdout, stderr: stderr, exitCode: exitCode)
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
        case .finished(let stdout, let stderr, let exitCode):
            guard exitCode == 0 else {
                throw YtdlpError.processFailed(stderr.trimmingCharacters(in: .whitespacesAndNewlines))
            }
            return stdout
        }
    }
}
