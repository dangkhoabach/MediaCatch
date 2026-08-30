import Foundation
import Testing
@testable import DKBDownloaderCore

struct DownloadManagerArgumentTests {
    private let tempDir = URL(fileURLWithPath: "/tmp/dkb-downloader/1")

    private func request(
        embedMetadata: Bool = false, audioOnly: Bool = false, cookiesBrowser: String? = nil, useAria2c: Bool = false
    ) -> StartDownloadRequest {
        StartDownloadRequest(
            url: "https://example.com/v", title: "t", formatSelector: "best", outputDir: "/tmp/out",
            outputFormat: "mp4", embedMetadata: embedMetadata, audioOnly: audioOnly,
            cookiesBrowser: cookiesBrowser, useAria2c: useAria2c
        )
    }

    @Test func basicRequestHasNoOptionalFlags() {
        let args = DownloadManager.buildArguments(request: request(), tempDir: tempDir, ffmpegURL: nil)

        #expect(args.contains("-f"))
        #expect(args.contains("best"))
        #expect(args.contains("--no-playlist"))
        #expect(args.contains("--progress"))
        #expect(!args.contains("--embed-thumbnail"))
        #expect(!args.contains("--cookies-from-browser"))
        #expect(!args.contains("--external-downloader"))
        #expect(args.last == "https://example.com/v", "url must always be the final argument")
    }

    @Test func embedMetadataAddsThumbnailChaptersAndSubs() {
        let args = DownloadManager.buildArguments(request: request(embedMetadata: true), tempDir: tempDir, ffmpegURL: nil)

        #expect(args.contains("--embed-thumbnail"))
        #expect(args.contains("--embed-chapters"))
        #expect(args.contains("--embed-metadata"))
        #expect(args.contains("--embed-subs"))
        let subLangsIndex = args.firstIndex(of: "--sub-langs")
        #expect(subLangsIndex.map { args[$0 + 1] } == "en,vi")
        #expect(!args.contains("-x"), "audio remux flags must not appear without audioOnly")
    }

    @Test func audioOnlyWithEmbedMetadataAddsRemuxFlags() {
        let args = DownloadManager.buildArguments(request: request(embedMetadata: true, audioOnly: true), tempDir: tempDir, ffmpegURL: nil)

        #expect(args.contains("-x"))
        let formatIndex = args.firstIndex(of: "--audio-format")
        #expect(formatIndex.map { args[$0 + 1] } == "best")
    }

    @Test func audioOnlyWithoutEmbedMetadataAddsNoRemuxFlags() {
        // Matches ytdlp.rs: the remux-for-thumbnail-embedding workaround only
        // applies when embed_metadata is also on.
        let args = DownloadManager.buildArguments(request: request(audioOnly: true), tempDir: tempDir, ffmpegURL: nil)
        #expect(!args.contains("-x"))
    }

    @Test func cookiesBrowserIsPassedThrough() {
        let args = DownloadManager.buildArguments(request: request(cookiesBrowser: "safari"), tempDir: tempDir, ffmpegURL: nil)
        let index = args.firstIndex(of: "--cookies-from-browser")
        #expect(index.map { args[$0 + 1] } == "safari")
    }

    @Test func emptyCookiesBrowserIsOmitted() {
        let args = DownloadManager.buildArguments(request: request(cookiesBrowser: ""), tempDir: tempDir, ffmpegURL: nil)
        #expect(!args.contains("--cookies-from-browser"))
    }

    @Test func aria2cAddsExternalDownloaderFlags() {
        let args = DownloadManager.buildArguments(request: request(useAria2c: true), tempDir: tempDir, ffmpegURL: nil)
        let index = args.firstIndex(of: "--external-downloader")
        #expect(index.map { args[$0 + 1] } == "aria2c")
        #expect(args.contains("--external-downloader-args"))
    }

    @Test func ffmpegLocationIsPassedWhenProvided() {
        let ffmpeg = URL(fileURLWithPath: "/opt/app/ffmpeg")
        let args = DownloadManager.buildArguments(request: request(), tempDir: tempDir, ffmpegURL: ffmpeg)
        let index = args.firstIndex(of: "--ffmpeg-location")
        #expect(index.map { args[$0 + 1] } == "/opt/app/ffmpeg")
    }

    @Test func outputTemplateUsesTempDirAndTitleExtPattern() {
        let args = DownloadManager.buildArguments(request: request(), tempDir: tempDir, ffmpegURL: nil)
        let index = args.firstIndex(of: "-o")
        #expect(index.map { args[$0 + 1] } == "/tmp/dkb-downloader/1/%(title)s.%(ext)s")
    }
}
