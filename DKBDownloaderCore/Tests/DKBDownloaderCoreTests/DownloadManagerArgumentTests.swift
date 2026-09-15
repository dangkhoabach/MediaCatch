import Foundation
import Testing
@testable import DKBDownloaderCore

struct DownloadManagerArgumentTests {
    private let tempDir = URL(fileURLWithPath: "/tmp/dkb-downloader/1")

    private func request(
        embedMetadata: Bool = false, audioOnly: Bool = false, cookiesBrowser: String? = nil, useAria2c: Bool = false,
        rateLimit: String? = nil, removeSponsorSegments: Bool = false, subtitleLanguages: String = "en,vi",
        cookiesFile: String? = nil, splitChapters: Bool = false
    ) -> StartDownloadRequest {
        StartDownloadRequest(
            url: "https://example.com/v", title: "t", formatSelector: "best", outputDir: "/tmp/out",
            outputFormat: "mp4", embedMetadata: embedMetadata, audioOnly: audioOnly,
            cookiesBrowser: cookiesBrowser, useAria2c: useAria2c,
            rateLimit: rateLimit, removeSponsorSegments: removeSponsorSegments,
            subtitleLanguages: subtitleLanguages,
            cookiesFile: cookiesFile, splitChapters: splitChapters
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

    /// Without the `--` separator, yt-dlp parses a dash-leading "URL" as an
    /// option — passing "--version" made it print its version instead of
    /// rejecting an invalid URL. Home's drag-and-drop fetches whatever was
    /// dropped without a confirmation step, so this must hold everywhere.
    @Test func urlIsSeparatedFromOptionsByADoubleDash() {
        let dashUrl = StartDownloadRequest(
            url: "--version", title: "t", formatSelector: "best",
            outputDir: "/tmp/out", outputFormat: "mp4"
        )
        let args = DownloadManager.buildArguments(request: dashUrl, tempDir: tempDir, ffmpegURL: nil)

        #expect(args.last == "--version")
        #expect(args.dropLast().last == "--", "the url must be preceded by an end-of-options separator")
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

    @Test func rateLimitIsPassedOnlyWhenSet() {
        let capped = DownloadManager.buildArguments(request: request(rateLimit: "5M"), tempDir: tempDir, ffmpegURL: nil)
        #expect(capped.firstIndex(of: "--limit-rate").map { capped[$0 + 1] } == "5M")

        let uncapped = DownloadManager.buildArguments(request: request(), tempDir: tempDir, ffmpegURL: nil)
        #expect(!uncapped.contains("--limit-rate"))
    }

    @Test func sponsorBlockRemovesOnlyTheSponsorCategory() {
        let args = DownloadManager.buildArguments(
            request: request(removeSponsorSegments: true), tempDir: tempDir, ffmpegURL: nil
        )
        #expect(args.firstIndex(of: "--sponsorblock-remove").map { args[$0 + 1] } == "sponsor")

        let off = DownloadManager.buildArguments(request: request(), tempDir: tempDir, ffmpegURL: nil)
        #expect(!off.contains("--sponsorblock-remove"))
    }

    @Test func subtitleLanguagesAreConfigurable() {
        let args = DownloadManager.buildArguments(
            request: request(embedMetadata: true, subtitleLanguages: "ja,ko"), tempDir: tempDir, ffmpegURL: nil
        )
        #expect(args.firstIndex(of: "--sub-langs").map { args[$0 + 1] } == "ja,ko")
    }

    @Test func cookiesFileReplacesTheBrowserOption() {
        // yt-dlp refuses both at once, so they can never both appear.
        let args = DownloadManager.buildArguments(
            request: request(cookiesBrowser: "safari", cookiesFile: "/tmp/cookies.txt"),
            tempDir: tempDir, ffmpegURL: nil
        )
        #expect(args.firstIndex(of: "--cookies").map { args[$0 + 1] } == "/tmp/cookies.txt")
        #expect(!args.contains("--cookies-from-browser"))
    }

    @Test func cookiesFileIsOmittedWhenUnset() {
        let args = DownloadManager.buildArguments(request: request(cookiesFile: ""), tempDir: tempDir, ffmpegURL: nil)
        #expect(!args.contains("--cookies"))
    }

    /// The chapter files must be pinned to the temp dir. yt-dlp's built-in
    /// `chapter:` template carries no directory and `-o` only sets the
    /// `default` key, so leaving it out writes them relative to the process's
    /// working directory — verified against 2026.08.19, where they landed in
    /// the shell's cwd instead of beside the video.
    @Test func splitChaptersAnchorsItsOutputTemplateToTheTempDir() {
        let args = DownloadManager.buildArguments(
            request: request(splitChapters: true), tempDir: tempDir, ffmpegURL: nil
        )
        #expect(args.contains("--split-chapters"))
        let chapterTemplate = args.first { $0.hasPrefix("chapter:") }
        #expect(chapterTemplate == "chapter:/tmp/dkb-downloader/1/%(title)s - %(section_number)03d %(section_title)s.%(ext)s")
    }

    @Test func splitChaptersFlagsAreAbsentByDefault() {
        let args = DownloadManager.buildArguments(request: request(), tempDir: tempDir, ffmpegURL: nil)
        #expect(!args.contains("--split-chapters"))
        #expect(!args.contains { $0.hasPrefix("chapter:") })
    }

    @Test func outputTemplateUsesTempDirAndTitleExtPattern() {
        let args = DownloadManager.buildArguments(request: request(), tempDir: tempDir, ffmpegURL: nil)
        let index = args.firstIndex(of: "-o")
        #expect(index.map { args[$0 + 1] } == "/tmp/dkb-downloader/1/%(title)s.%(ext)s")
    }
}
