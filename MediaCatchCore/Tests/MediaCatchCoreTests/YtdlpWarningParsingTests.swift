import Foundation
import Testing
@testable import MediaCatchCore

/// Pulling yt-dlp's `WARNING:` lines out of stderr, which is how a degraded
/// extraction announces itself while still exiting zero.
struct YtdlpWarningParsingTests {
    @Test func stripsThePrefixAndIgnoresEverythingElse() {
        let warnings = YtdlpClient.parseWarnings([
            "[youtube] Extracting URL: abc",
            "WARNING: some formats may be missing",
            "[info] Downloading 1 format(s)",
        ])
        #expect(warnings == ["some formats may be missing"])
    }

    /// yt-dlp repeats the same notice once per extraction step on some sites;
    /// showing it three times would read as three separate problems.
    @Test func deduplicatesWhileKeepingFirstAppearanceOrder() {
        let warnings = YtdlpClient.parseWarnings([
            "WARNING: b",
            "WARNING: a",
            "WARNING: b",
        ])
        #expect(warnings == ["b", "a"])
    }

    @Test func toleratesLeadingWhitespaceAndDropsEmptyBodies() {
        let warnings = YtdlpClient.parseWarnings(["   WARNING: indented", "WARNING:", "WARNING:    "])
        #expect(warnings == ["indented"])
    }

    @Test func aCleanRunHasNoWarnings() {
        #expect(YtdlpClient.parseWarnings([]).isEmpty)
        #expect(YtdlpClient.parseWarnings(["[info] all good"]).isEmpty)
    }

    /// The real thing, verbatim from yt-dlp 2026.08.19 — the notice that
    /// prompted all of this, and the one most likely to matter later.
    @Test func handlesTheRealJavaScriptRuntimeWarning() {
        let line = "WARNING: [youtube] No supported JavaScript runtime could be found. "
            + "YouTube extraction without a JS runtime has been deprecated, and some formats may be missing."
        let warnings = YtdlpClient.parseWarnings([line])
        #expect(warnings.count == 1)
        #expect(warnings[0].hasPrefix("[youtube] No supported JavaScript runtime"))
        #expect(!warnings[0].contains("WARNING:"))
    }

    @Test func failureMessagePrefersRealErrorsOverWarnings() {
        let message = YtdlpClient.failureMessage(from: [
            "WARNING: noise",
            "ERROR: the actual problem",
        ])
        #expect(message == "ERROR: the actual problem")
    }

    @Test func failureMessageFallsBackToWarningsRatherThanSayingNothing() {
        #expect(YtdlpClient.failureMessage(from: ["WARNING: only this"]) == "WARNING: only this")
        #expect(YtdlpClient.failureMessage(from: []).isEmpty)
    }
}
