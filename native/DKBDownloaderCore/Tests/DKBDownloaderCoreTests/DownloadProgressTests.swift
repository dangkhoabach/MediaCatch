import Testing
@testable import DKBDownloaderCore

struct DownloadProgressTests {
    @Test func parsesAWellFormedProgressLine() {
        let progress = parseDownloadProgressLine("DKB| 42.0%| 1.23MiB/s|  00:07")
        #expect(progress == DownloadProgress(percent: "42.0%", speed: "1.23MiB/s", eta: "00:07"))
    }

    @Test func ignoresTheFinalFilepathPrintLine() {
        // The other stdout line start_download expects — --print
        // after_move:filepath — carries no "DKB|" marker.
        #expect(parseDownloadProgressLine("/Users/me/Downloads/video.mp4") == nil)
    }

    @Test func returnsNilForATruncatedLine() {
        #expect(parseDownloadProgressLine("DKB|50%") == nil)
    }
}
