import Foundation
import Testing
@testable import DKBDownloaderCore

struct DownloadManagerMoveTests {
    @Test func movesFileToOutputDirAndReturnsNewPath() throws {
        let fm = FileManager.default
        let tempDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let outputDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: tempDir, withIntermediateDirectories: true)
        try fm.createDirectory(at: outputDir, withIntermediateDirectories: true)
        defer {
            try? fm.removeItem(at: tempDir)
            try? fm.removeItem(at: outputDir)
        }

        let sourceFile = tempDir.appendingPathComponent("video.mp4")
        try "content".write(to: sourceFile, atomically: true, encoding: .utf8)

        let moved = DownloadManager.moveToOutputDir(tempPath: sourceFile.path, outputDir: outputDir.path)

        let expectedPath = outputDir.appendingPathComponent("video.mp4").path
        #expect(moved == expectedPath)
        #expect(fm.fileExists(atPath: expectedPath))
        #expect(!fm.fileExists(atPath: sourceFile.path), "source file should be gone after a move")
    }

    @Test func returnsNilWhenSourceFileDoesNotExist() {
        let moved = DownloadManager.moveToOutputDir(tempPath: "/nonexistent/video.mp4", outputDir: "/tmp")
        #expect(moved == nil)
    }

    /// Re-downloading a video whose file is already in the output folder used
    /// to fail the move *and* the copy fallback, reporting an error and
    /// deleting the finished file with its temp dir.
    @Test func numbersTheFilenameWhenTheOutputFileAlreadyExists() throws {
        let fm = FileManager.default
        let tempDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let outputDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: tempDir, withIntermediateDirectories: true)
        try fm.createDirectory(at: outputDir, withIntermediateDirectories: true)
        defer {
            try? fm.removeItem(at: tempDir)
            try? fm.removeItem(at: outputDir)
        }
        try "existing".write(to: outputDir.appendingPathComponent("video.mp4"), atomically: true, encoding: .utf8)

        let first = tempDir.appendingPathComponent("video.mp4")
        try "first".write(to: first, atomically: true, encoding: .utf8)
        #expect(DownloadManager.moveToOutputDir(tempPath: first.path, outputDir: outputDir.path)
            == outputDir.appendingPathComponent("video (1).mp4").path)

        let second = tempDir.appendingPathComponent("video.mp4")
        try "second".write(to: second, atomically: true, encoding: .utf8)
        #expect(DownloadManager.moveToOutputDir(tempPath: second.path, outputDir: outputDir.path)
            == outputDir.appendingPathComponent("video (2).mp4").path)

        // The pre-existing file must be left untouched by both moves.
        #expect(try String(contentsOf: outputDir.appendingPathComponent("video.mp4"), encoding: .utf8) == "existing")
    }

    @Test func numbersAnExtensionlessFilenameWithoutAddingADot() throws {
        let fm = FileManager.default
        let tempDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let outputDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: tempDir, withIntermediateDirectories: true)
        try fm.createDirectory(at: outputDir, withIntermediateDirectories: true)
        defer {
            try? fm.removeItem(at: tempDir)
            try? fm.removeItem(at: outputDir)
        }
        try "existing".write(to: outputDir.appendingPathComponent("video"), atomically: true, encoding: .utf8)

        let source = tempDir.appendingPathComponent("video")
        try "new".write(to: source, atomically: true, encoding: .utf8)

        #expect(DownloadManager.moveToOutputDir(tempPath: source.path, outputDir: outputDir.path)
            == outputDir.appendingPathComponent("video (1)").path)
    }

    /// `--print after_move:filepath` reports only the merged video, so the
    /// per-chapter files yt-dlp writes alongside it would be deleted with the
    /// temp dir if nothing else picked them up.
    @Test func leftoverChapterFilesAreMovedOutToo() throws {
        let fm = FileManager.default
        let tempDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let outputDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: tempDir, withIntermediateDirectories: true)
        try fm.createDirectory(at: outputDir, withIntermediateDirectories: true)
        defer {
            try? fm.removeItem(at: tempDir)
            try? fm.removeItem(at: outputDir)
        }

        for name in ["v - 001 Intro.mp4", "v - 002 Middle.mp4"] {
            try "chapter".write(to: tempDir.appendingPathComponent(name), atomically: true, encoding: .utf8)
        }
        // Subdirectories aren't yt-dlp output; only regular files move.
        try fm.createDirectory(at: tempDir.appendingPathComponent("sub"), withIntermediateDirectories: true)

        let moved = DownloadManager.moveLeftoverFiles(tempDir: tempDir, outputDir: outputDir.path)

        #expect(moved.count == 2)
        #expect(fm.fileExists(atPath: outputDir.appendingPathComponent("v - 001 Intro.mp4").path))
        #expect(fm.fileExists(atPath: outputDir.appendingPathComponent("v - 002 Middle.mp4").path))
        #expect(fm.fileExists(atPath: tempDir.appendingPathComponent("sub").path))
    }

    @Test func movingLeftoversFromAnEmptyTempDirDoesNothing() throws {
        let fm = FileManager.default
        let tempDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tempDir) }

        #expect(DownloadManager.moveLeftoverFiles(tempDir: tempDir, outputDir: "/tmp").isEmpty)
    }
}
