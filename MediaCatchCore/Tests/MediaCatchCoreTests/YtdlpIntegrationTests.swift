import Foundation
import Testing
@testable import MediaCatchCore

/// Real-binary, real-network verification that ProcessRunner
/// actually works end-to-end with the bundled yt-dlp sidecar, not just with
/// toy /bin/sh scripts. Gated behind RUN_YTDLP_INTEGRATION_TESTS=1 — see
/// IntegrationTestSupport.swift.
struct YtdlpIntegrationTests {
    @Test func realBinaryReportsItsVersion() async throws {
        guard integrationTestsEnabled, let ytdlp = ytdlpBinaryURL() else { return }

        let runner = try ProcessRunner(executableURL: ytdlp, arguments: ["--version"])
        var lines: [String] = []
        var terminatedCode: Int32?
        for await event in runner.events {
            switch event {
            case .stdoutLine(let line): lines.append(line)
            case .stderrLine: break
            case .terminated(let code): terminatedCode = code
            }
        }

        #expect(terminatedCode == 0)
        #expect(lines.first?.isEmpty == false)
    }

    /// Downloads a tiny, well-known, permanently-public video ("Me at the
    /// zoo", the first video ever uploaded to YouTube) at the smallest
    /// available format, using the exact same
    /// --progress-template marker start_download uses, and verifies: real
    /// progress lines parse correctly, the process terminates cleanly, and
    /// the file actually lands on disk.
    @Test func downloadsARealTinyVideoWithParsableProgress() async throws {
        guard integrationTestsEnabled, let ytdlp = ytdlpBinaryURL() else { return }

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("dkb-downloader-poc-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let outputTemplate = tempDir.appendingPathComponent("%(title)s.%(ext)s").path
        let runner = try ProcessRunner(
            executableURL: ytdlp,
            arguments: [
                "-f", "worstaudio",
                "-o", outputTemplate,
                "--no-playlist",
                // yt-dlp silently drops all progress output (including a
                // custom --progress-template) whenever stdout isn't a real
                // tty, which a Pipe never is — --progress forces it back on,
                // exactly the same reason ytdlp.rs::start_download needs it.
                "--progress",
                "--newline",
                "--progress-template", "download:DKB|%(progress._percent_str)s|%(progress._speed_str)s|%(progress._eta_str)s",
                "--print", "after_move:filepath",
                stableTestVideoURL,
            ]
        )

        var progressEvents: [DownloadProgress] = []
        var finalPath: String?
        var terminatedCode: Int32?
        for await event in runner.events {
            switch event {
            case .stdoutLine(let line):
                if let progress = parseDownloadProgressLine(line) {
                    progressEvents.append(progress)
                } else if !line.isEmpty {
                    finalPath = line
                }
            case .stderrLine:
                break
            case .terminated(let code):
                terminatedCode = code
            }
        }

        #expect(terminatedCode == 0)
        #expect(!progressEvents.isEmpty, "expected at least one parsed DKB| progress line from a real download")
        let path = try #require(finalPath)
        #expect(FileManager.default.fileExists(atPath: path))
    }
}
