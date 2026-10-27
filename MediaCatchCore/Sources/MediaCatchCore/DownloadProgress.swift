import Foundation

public struct DownloadProgress: Sendable, Equatable {
    public let percent: String
    public let speed: String
    public let eta: String

    public init(percent: String, speed: String, eta: String) {
        self.percent = percent
        self.speed = speed
        self.eta = eta
    }
}

/// Parses one line of yt-dlp's `--progress-template` output built with the
/// `DKB|%(progress._percent_str)s|%(progress._speed_str)s|%(progress._eta_str)s`
/// template (see `ytdlp.rs::start_download`) — the `DKB|` marker distinguishes
/// this from yt-dlp's other stdout line (the final `--print after_move:filepath`),
/// which carries no such prefix.
public func parseDownloadProgressLine(_ line: String) -> DownloadProgress? {
    let trimmed = line.trimmingCharacters(in: .whitespaces)
    guard trimmed.hasPrefix("DKB|") else { return nil }
    let rest = trimmed.dropFirst("DKB|".count)
    let parts = rest.split(separator: "|", maxSplits: 2, omittingEmptySubsequences: false)
    guard parts.count == 3 else { return nil }
    return DownloadProgress(
        percent: parts[0].trimmingCharacters(in: .whitespaces),
        speed: parts[1].trimmingCharacters(in: .whitespaces),
        eta: parts[2].trimmingCharacters(in: .whitespaces)
    )
}
