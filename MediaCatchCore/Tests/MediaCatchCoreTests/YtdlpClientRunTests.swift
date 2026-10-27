import Foundation
import Testing
@testable import MediaCatchCore

/// `YtdlpClient.run`'s process handling, exercised with `/bin/sh` instead of
/// the real yt-dlp binary so these stay fast and need no network.
struct YtdlpClientRunTests {
    private let shell = URL(fileURLWithPath: "/bin/sh")

    @Test func returnsStdoutOnACleanExit() async throws {
        let output = try await YtdlpClient.run(shell, ["-c", "echo hello"])
        #expect(output.stdout == "hello")
        #expect(output.warnings.isEmpty)
    }

    /// Warnings come back from a run that *succeeded* — that's the whole
    /// point, since a degraded extraction still exits zero.
    @Test func collectsWarningsFromASuccessfulRun() async throws {
        let output = try await YtdlpClient.run(
            shell, ["-c", "echo 'WARNING: formats may be missing' 1>&2; echo '[info] noise' 1>&2; echo data"]
        )
        #expect(output.stdout == "data")
        #expect(output.warnings == ["formats may be missing"])
    }

    @Test func throwsStderrOnANonZeroExit() async throws {
        await #expect(throws: YtdlpError.processFailed("boom")) {
            try await YtdlpClient.run(shell, ["-c", "echo boom 1>&2; exit 3"])
        }
    }

    /// YouTube extraction currently warns on every single call, so letting
    /// warnings into the error text would bury the actual reason under an
    /// unrelated notice.
    @Test func aFailureReportsTheErrorWithoutThePrecedingWarnings() async throws {
        await #expect(throws: YtdlpError.processFailed("ERROR: nope")) {
            try await YtdlpClient.run(shell, ["-c", "echo 'WARNING: ignore me' 1>&2; echo 'ERROR: nope' 1>&2; exit 1"])
        }
    }

    /// …but a failure that only ever printed warnings must still say
    /// something, rather than reporting an empty reason.
    @Test func aFailureWithNothingButWarningsStillReportsThem() async throws {
        await #expect(throws: YtdlpError.processFailed("WARNING: all I have")) {
            try await YtdlpClient.run(shell, ["-c", "echo 'WARNING: all I have' 1>&2; exit 1"])
        }
    }

    /// Separate messages must stay separate: ProcessRunner strips each line's
    /// newline, so accumulating them into one string ran them together.
    @Test func multipleStderrLinesKeepTheirLineBreaks() async throws {
        await #expect(throws: YtdlpError.processFailed("first\nsecond")) {
            try await YtdlpClient.run(shell, ["-c", "echo first 1>&2; echo second 1>&2; exit 1"])
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
