import Foundation
import Testing
@testable import DKBDownloaderCore

/// `YtdlpClient.run`'s process handling, exercised with `/bin/sh` instead of
/// the real yt-dlp binary so these stay fast and need no network.
struct YtdlpClientRunTests {
    private let shell = URL(fileURLWithPath: "/bin/sh")

    @Test func returnsStdoutOnACleanExit() async throws {
        let output = try await YtdlpClient.run(shell, ["-c", "echo hello"])
        #expect(output == "hello")
    }

    @Test func throwsStderrOnANonZeroExit() async throws {
        await #expect(throws: YtdlpError.processFailed("boom")) {
            try await YtdlpClient.run(shell, ["-c", "echo boom 1>&2; exit 3"])
        }
    }

    /// A stalled network read produces no output and never exits, which used
    /// to leave the fetch spinner going forever with no way out.
    @Test func timesOutAndKillsAProcessThatOutlivesItsLimit() async throws {
        let started = ContinuousClock.now

        await #expect(throws: YtdlpError.timedOut) {
            try await YtdlpClient.run(shell, ["-c", "sleep 30"], timeout: .milliseconds(500))
        }

        let elapsed = ContinuousClock.now - started
        #expect(elapsed < .seconds(10), "run() must return at its timeout, not wait out the process")
    }

    /// Cancelling the calling task has to kill the child too — otherwise a
    /// cancelled fetch leaves yt-dlp running to completion in the background
    /// with nobody left to read its output.
    @Test func cancellingTheCallingTaskKillsTheProcess() async throws {
        let task = Task {
            try await YtdlpClient.run(shell, ["-c", "sleep 30"], timeout: .seconds(60))
        }
        // Let it actually spawn before cancelling.
        try await Task.sleep(for: .milliseconds(300))

        let started = ContinuousClock.now
        task.cancel()
        _ = try? await task.value
        let elapsed = ContinuousClock.now - started

        #expect(elapsed < .seconds(10), "a cancelled run() must not wait out the process")
    }
}
