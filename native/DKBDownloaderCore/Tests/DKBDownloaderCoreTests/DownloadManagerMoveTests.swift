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
}
