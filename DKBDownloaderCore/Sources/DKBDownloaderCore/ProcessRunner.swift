import Foundation

/// One event surfaced while a spawned process runs. Lines are UTF-8 decoded
/// and stripped of their trailing newline; `terminated` always arrives last.
public enum ProcessEvent: Sendable, Equatable {
    case stdoutLine(String)
    case stderrLine(String)
    case terminated(exitCode: Int32)
}

/// Spawns a process and streams its stdout/stderr line-by-line while it is
/// still running, instead of `Foundation.Process`'s default "wait for exit,
/// then read everything" shape — this is what lets a `DownloadManager` react
/// to yt-dlp's `--progress-template` output in real time, mirroring what
/// `tauri_plugin_shell::Command`'s `CommandEvent` stream gave the Rust
/// version for free.
///
/// `@unchecked Sendable`: all mutable state (`stdoutBuffer`/`stderrBuffer`)
/// is only ever touched while holding `lock`, since `Pipe`'s
/// `readabilityHandler` callbacks and `Process.terminationHandler` both fire
/// on background dispatch queues Foundation owns, not on any queue this type
/// controls.
public final class ProcessRunner: @unchecked Sendable {
    private let process: Process
    private let stdoutPipe = Pipe()
    private let stderrPipe = Pipe()
    private let lock = NSLock()
    private var stdoutBuffer = Data()
    private var stderrBuffer = Data()
    private var finished = false

    // `terminationHandler` firing does not guarantee every byte the child
    // already wrote has been delivered to our `readabilityHandler` yet —
    // that delivery is dispatched asynchronously by Foundation and can lag
    // behind process exit under system load. Gating `finish()` on all three
    // signals (both pipes' EOF plus the exit code) instead of the exit code
    // alone is what actually guarantees no trailing output gets lost; the
    // Phase 4 test suite caught this as a real, load-dependent flake before
    // this fix.
    private var terminationCode: Int32?
    private var stdoutEOF = false
    private var stderrEOF = false

    public let events: AsyncStream<ProcessEvent>
    private let continuation: AsyncStream<ProcessEvent>.Continuation

    public var pid: Int32 { process.processIdentifier }
    public var isRunning: Bool { process.isRunning }

    // A real installed .app launched from Finder/Dock/Spotlight has no shell
    // login PATH — it only inherits launchd's minimal default, which doesn't
    // include Homebrew's bin dirs. yt-dlp itself (and its aria2c child
    // process, spawned as a bare command name) relies on PATH to find
    // Homebrew-installed tools, so append the common Homebrew/local prefixes
    // here rather than leaving this to fail silently in a packaged build
    // while working fine when launched from Xcode/Terminal (which do inherit
    // a shell PATH).
    private static let supplementalPathEntries = [
        "/opt/homebrew/bin", "/opt/homebrew/sbin", "/usr/local/bin", "/usr/local/sbin",
    ]

    public init(executableURL: URL, arguments: [String], currentDirectoryURL: URL? = nil) throws {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments
        if let currentDirectoryURL {
            process.currentDirectoryURL = currentDirectoryURL
        }
        var environment = ProcessInfo.processInfo.environment
        let existingPath = environment["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        let existingEntries = Set(existingPath.split(separator: ":").map(String.init))
        let newEntries = Self.supplementalPathEntries.filter { !existingEntries.contains($0) }
        environment["PATH"] = (newEntries + [existingPath]).joined(separator: ":")
        process.environment = environment
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        self.process = process

        var continuation: AsyncStream<ProcessEvent>.Continuation!
        self.events = AsyncStream { continuation = $0 }
        self.continuation = continuation

        // Safe to capture `self` from here on — every stored property above
        // has a value, which Swift requires before a class's `self` can be
        // captured by an escaping closure inside its own initializer.
        stdoutPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            self?.handleData(handle.availableData, isStdout: true)
        }
        stderrPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            self?.handleData(handle.availableData, isStdout: false)
        }
        process.terminationHandler = { [weak self] proc in
            self?.markTerminated(exitCode: proc.terminationStatus)
        }

        try process.run()
    }

    private func handleData(_ data: Data, isStdout: Bool) {
        lock.lock()
        defer { lock.unlock() }
        guard !finished else { return }

        // Empty `availableData` means EOF on this pipe (the child closed its
        // end) — one of the 3 signals `maybeFinish` waits on, not something
        // to ignore.
        guard !data.isEmpty else {
            if isStdout { stdoutEOF = true } else { stderrEOF = true }
            maybeFinish()
            return
        }

        if isStdout {
            stdoutBuffer.append(data)
            drainLines(from: &stdoutBuffer) { continuation.yield(.stdoutLine($0)) }
        } else {
            stderrBuffer.append(data)
            drainLines(from: &stderrBuffer) { continuation.yield(.stderrLine($0)) }
        }
    }

    private func markTerminated(exitCode: Int32) {
        lock.lock()
        defer { lock.unlock() }
        guard !finished else { return }
        terminationCode = exitCode
        maybeFinish()
    }

    /// Must be called with `lock` already held.
    private func maybeFinish() {
        guard let exitCode = terminationCode, stdoutEOF, stderrEOF else { return }
        finished = true

        // Flush whatever partial, not-yet-newline-terminated line remains in
        // each buffer — yt-dlp always newline-terminates its output, but
        // don't silently drop data from a process that doesn't.
        if !stdoutBuffer.isEmpty, let line = String(data: stdoutBuffer, encoding: .utf8) {
            continuation.yield(.stdoutLine(line))
        }
        if !stderrBuffer.isEmpty, let line = String(data: stderrBuffer, encoding: .utf8) {
            continuation.yield(.stderrLine(line))
        }
        stdoutBuffer.removeAll()
        stderrBuffer.removeAll()

        stdoutPipe.fileHandleForReading.readabilityHandler = nil
        stderrPipe.fileHandleForReading.readabilityHandler = nil
        continuation.yield(.terminated(exitCode: exitCode))
        continuation.finish()
    }

    private func drainLines(from buffer: inout Data, emit: (String) -> Void) {
        while let newlineIndex = buffer.firstIndex(of: 0x0A) {
            let lineData = buffer[..<newlineIndex]
            buffer.removeSubrange(...newlineIndex)
            if let line = String(data: lineData, encoding: .utf8) {
                emit(line)
            }
        }
    }

    /// Suspends the process via `SIGSTOP` — its in-flight network reads/
    /// writes just stall, the socket and any partial output file stay
    /// intact. Sent straight to the PID through the `Darwin` syscall instead
    /// of shelling out to `/bin/kill` the way the Rust version has to (`std`
    /// has no direct signal-sending binding) — no extra process spawned.
    @discardableResult
    public func suspend() -> Bool {
        kill(pid, SIGSTOP) == 0
    }

    @discardableResult
    public func resume() -> Bool {
        kill(pid, SIGCONT) == 0
    }

    /// Requests termination (SIGTERM) for a user-initiated Cancel. Callers
    /// that need to distinguish "I canceled this" from "it errored out" once
    /// `terminated` arrives must track that themselves *before* calling this
    /// — the exit code alone doesn't reliably tell the two apart, exactly
    /// the same reason `ytdlp.rs::start_download` checks a `was_canceled` DB
    /// flag instead of trusting the child's exit status.
    public func terminate() {
        process.terminate()
    }
}
