import Foundation
import Testing
@testable import MediaCatchCore

private let shell = URL(fileURLWithPath: "/bin/sh")

struct ProcessRunnerTests {
    @Test func capturesStdoutLinesInOrderAndTerminatesWithExitCodeZero() async throws {
        let runner = try ProcessRunner(executableURL: shell, arguments: ["-c", "echo one; echo two; echo three"])

        var lines: [String] = []
        var terminatedCode: Int32?
        for await event in runner.events {
            switch event {
            case .stdoutLine(let line): lines.append(line)
            case .stderrLine: break
            case .terminated(let code): terminatedCode = code
            }
        }

        #expect(lines == ["one", "two", "three"])
        #expect(terminatedCode == 0)
    }

    @Test func capturesStderrSeparatelyFromStdout() async throws {
        let runner = try ProcessRunner(executableURL: shell, arguments: ["-c", "echo out-line; echo err-line 1>&2"])

        var stdoutLines: [String] = []
        var stderrLines: [String] = []
        for await event in runner.events {
            switch event {
            case .stdoutLine(let line): stdoutLines.append(line)
            case .stderrLine(let line): stderrLines.append(line)
            case .terminated: break
            }
        }

        #expect(stdoutLines == ["out-line"])
        #expect(stderrLines == ["err-line"])
    }

    @Test func reportsANonZeroExitCode() async throws {
        let runner = try ProcessRunner(executableURL: shell, arguments: ["-c", "exit 7"])

        var terminatedCode: Int32?
        for await event in runner.events {
            if case .terminated(let code) = event { terminatedCode = code }
        }

        #expect(terminatedCode == 7)
    }

    /// SIGSTOP genuinely pauses the child (no more
    /// output while stopped), SIGCONT genuinely resumes it, and the whole
    /// thing behaves the way `pause_download`/`resume_download` need it to
    /// for a real yt-dlp download's network reads to actually stall.
    @Test func suspendStopsOutputAndResumeContinuesIt() async throws {
        // Prints an incrementing counter every 0.1s, up to 30 (3s total if
        // never paused) — long enough to comfortably observe a pause window.
        let script = "i=0; while [ $i -lt 30 ]; do i=$((i+1)); echo $i; sleep 0.1; done"
        let runner = try ProcessRunner(executableURL: shell, arguments: ["-c", script])

        actor LineCollector {
            private(set) var lines: [String] = []
            func append(_ line: String) { lines.append(line) }
        }
        let collector = LineCollector()
        let collectorTask = Task {
            for await event in runner.events {
                if case .stdoutLine(let line) = event { await collector.append(line) }
            }
        }

        // Let it produce a couple of lines, then stop it.
        try await Task.sleep(for: .milliseconds(350))
        #expect(runner.suspend())
        let countAtSuspend = await collector.lines.count
        #expect(countAtSuspend > 0)

        // While stopped, no new output should appear no matter how long we wait.
        try await Task.sleep(for: .milliseconds(500))
        let countStillSuspended = await collector.lines.count
        #expect(countStillSuspended == countAtSuspend, "process kept producing output while suspended")

        #expect(runner.resume())
        try await Task.sleep(for: .milliseconds(400))
        let countAfterResume = await collector.lines.count
        #expect(countAfterResume > countAtSuspend, "process did not resume after SIGCONT")

        runner.terminate()
        await collectorTask.value
    }

    /// Canceling (or quitting with) a *paused* download has to actually kill
    /// the child. Unlike Linux — where a SIGTERM sent to a SIGSTOPped process
    /// stays pending until it's resumed — Darwin acts on it right away, so
    /// `cancel`/`terminateAll` need no SIGCONT first. Pinned here because
    /// that difference is easy to "fix" based on the Linux behavior.
    @Test func aSuspendedProcessStillActsOnTerminate() async throws {
        let runner = try ProcessRunner(executableURL: shell, arguments: ["-c", "sleep 30"])
        #expect(runner.suspend())

        runner.terminate()

        // Polled rather than a fixed sleep: SIGTERM delivery is near-instant
        // but not synchronous with `terminate()` returning.
        var attempts = 0
        while runner.isRunning, attempts < 50 {
            try await Task.sleep(for: .milliseconds(20))
            attempts += 1
        }

        #expect(!runner.isRunning, "a stopped process should still act on SIGTERM on Darwin")
        // No-ops if it already exited; only matters if the assert above
        // failed, so a regression doesn't leave a stopped process behind.
        runner.resume()
        runner.terminate()
    }

    /// A caller that marks "I canceled this"
    /// *before* calling terminate() can reliably tell that apart from a real
    /// failure once `terminated` arrives, the same pattern
    /// `start_download`'s `was_canceled` DB check relies on instead of
    /// trusting the child's exit code (SIGTERM doesn't yield a stable,
    /// distinguishable code across process kinds).
    @Test func externalCancelFlagDistinguishesUserCancelFromRealFailure() async throws {
        let runner = try ProcessRunner(executableURL: shell, arguments: ["-c", "sleep 30"])

        actor CancelFlag {
            private(set) var wasCanceled = false
            func markCanceled() { wasCanceled = true }
        }
        let flag = CancelFlag()

        // Mirrors the real call order: mark canceled first, then kill —
        // exactly what a Cancel button's handler would do before the
        // terminated event has any chance to race ahead of it.
        await flag.markCanceled()
        runner.terminate()

        var terminatedCode: Int32?
        for await event in runner.events {
            if case .terminated(let code) = event { terminatedCode = code }
        }

        #expect(terminatedCode != 0, "a killed sleep should not report a clean exit")
        #expect(await flag.wasCanceled, "the externally-tracked flag must still say canceled once terminated arrives")
    }
}
