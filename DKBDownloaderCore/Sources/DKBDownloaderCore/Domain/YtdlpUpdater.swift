import CryptoKit
import Foundation

struct GithubRelease: Decodable {
    let tagName: String
    enum CodingKeys: String, CodingKey { case tagName = "tag_name" }
}

enum YtdlpUpdaterError: Error, Equatable {
    case checksumMissing
    case checksumMismatch
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

        let checksumsURL = URL(string: "https://github.com/yt-dlp/yt-dlp/releases/download/\(release.tagName)/SHA2-256SUMS")!
        let (checksumsData, _) = try await urlSession.data(from: checksumsURL)
        guard let checksumsText = String(data: checksumsData, encoding: .utf8),
              let expectedHash = checksumsText
                  .split(separator: "\n")
                  .first(where: { $0.hasSuffix("yt-dlp_macos") })
                  .map({ $0.split(separator: " ")[0] })
        else {
            throw YtdlpUpdaterError.checksumMissing
        }

        let actualHash = SHA256.hash(data: binaryData).compactMap { String(format: "%02x", $0) }.joined()
        guard actualHash == expectedHash else {
            throw YtdlpUpdaterError.checksumMismatch
        }

        try FileManager.default.createDirectory(at: binDirectory, withIntermediateDirectories: true)
        let binPath = binDirectory.appendingPathComponent("yt-dlp")
        let tmpPath = binDirectory.appendingPathComponent("yt-dlp.tmp-\(UUID().uuidString)")
        try binaryData.write(to: tmpPath)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tmpPath.path)
        _ = try FileManager.default.replaceItemAt(binPath, withItemAt: tmpPath)

        return release.tagName
    }
}
