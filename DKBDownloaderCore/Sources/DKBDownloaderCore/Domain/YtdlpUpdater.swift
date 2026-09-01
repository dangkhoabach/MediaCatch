import Foundation

struct GithubRelease: Decodable {
    let tagName: String
    enum CodingKeys: String, CodingKey { case tagName = "tag_name" }
}

/// Checks GitHub for a newer yt-dlp release than the one currently in use
/// and, if found, downloads it into the app data dir — independent of this
/// app's own release cycle. Mirrors `ytdlp.rs::update_ytdlp` (macOS-only
/// asset name, per the plan's decision to drop the Windows branch).
public struct YtdlpUpdater: Sendable {
    let ytdlpURL: URL
    let binDirectory: URL

    public init(ytdlpURL: URL, binDirectory: URL) {
        self.ytdlpURL = ytdlpURL
        self.binDirectory = binDirectory
    }

    /// Returns `nil` when already up to date, or the new version string
    /// when it just updated.
    public func updateIfNeeded(urlSession: URLSession = .shared) async throws -> String? {
        let currentVersion = try await YtdlpClient.run(ytdlpURL, ["--version"])
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let releaseURL = URL(string: "https://api.github.com/repos/yt-dlp/yt-dlp/releases/latest")!
        let (releaseData, _) = try await urlSession.data(from: releaseURL)
        let release = try JSONDecoder().decode(GithubRelease.self, from: releaseData)

        guard release.tagName != currentVersion else { return nil }

        let assetURL = URL(string: "https://github.com/yt-dlp/yt-dlp/releases/download/\(release.tagName)/yt-dlp_macos")!
        let (binaryData, _) = try await urlSession.data(from: assetURL)

        try FileManager.default.createDirectory(at: binDirectory, withIntermediateDirectories: true)
        let binPath = binDirectory.appendingPathComponent("yt-dlp")
        try binaryData.write(to: binPath)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: binPath.path)

        return release.tagName
    }
}
