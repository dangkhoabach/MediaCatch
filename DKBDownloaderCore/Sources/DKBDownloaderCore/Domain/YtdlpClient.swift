import Foundation

public enum YtdlpError: Error, Equatable, Sendable {
    case processFailed(String)
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

    public func fetchVideoInfo(url: String, cookiesBrowser: String? = nil) async throws -> VideoInfo {
        var args = ["-j", "--no-playlist", "--no-warnings"]
        Self.appendCookiesArg(&args, cookiesBrowser)
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

    /// Reads cookies straight from an installed browser's own cookie store —
    /// shared by `fetchVideoInfo` and `DownloadManager` so both use the same
    /// browser choice consistently.
    static func appendCookiesArg(_ args: inout [String], _ cookiesBrowser: String?) {
        if let browser = cookiesBrowser, !browser.isEmpty {
            args.append("--cookies-from-browser")
            args.append(browser)
        }
    }

    /// Runs `executable` to completion and returns its stdout, throwing the
    /// trimmed stderr as a plain error message on non-zero exit — mirrors
    /// `fetch_video_info`/`dump_playlist`'s error handling in ytdlp.rs.
    static func run(_ executable: URL, _ args: [String]) async throws -> String {
        let runner = try ProcessRunner(executableURL: executable, arguments: args)
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
        guard exitCode == 0 else {
            throw YtdlpError.processFailed(stderr.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return stdout
    }
}
