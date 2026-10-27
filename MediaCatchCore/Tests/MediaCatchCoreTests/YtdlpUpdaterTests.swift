import CryptoKit
import Foundation
import Testing
@testable import MediaCatchCore

/// Intercepts every request made through the injected `URLSession` so these
/// tests never touch the real network. Routes by whether the URL ends in
/// the GitHub API releases path, the asset name, or the checksums file name.
final class MockURLProtocol: URLProtocol {
    nonisolated(unsafe) static var releaseJSON: Data = Data()
    nonisolated(unsafe) static var assetData: Data = Data()
    nonisolated(unsafe) static var checksumsData: Data = Data()

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let url = request.url!
        let data: Data
        if url.path.contains("/releases/latest") {
            data = Self.releaseJSON
        } else if url.lastPathComponent == "SHA2-256SUMS" {
            data = Self.checksumsData
        } else {
            data = Self.assetData
        }
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private func mockSession() -> URLSession {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [MockURLProtocol.self]
    return URLSession(configuration: config)
}

/// A fake `yt-dlp` executable that just prints a fixed version string for
/// `--version`, standing in for the real binary so these tests don't depend
/// on it being installed.
private func fakeYtdlpURL(version: String) throws -> URL {
    let scriptURL = FileManager.default.temporaryDirectory.appendingPathComponent("fake-yt-dlp-\(UUID().uuidString)")
    try "#!/bin/sh\necho \"\(version)\"\n".write(to: scriptURL, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)
    return scriptURL
}

private func sha256Hex(_ data: Data) -> String {
    SHA256.hash(data: data).compactMap { String(format: "%02x", $0) }.joined()
}

// Serialized: all 4 tests route through `MockURLProtocol`'s shared static
// response state, so they can't run concurrently without racing each other.
@Suite(.serialized)
struct YtdlpUpdaterTests {
    @Test func returnsNilWhenAlreadyUpToDate() async throws {
        let ytdlpURL = try fakeYtdlpURL(version: "2024.01.01")
        let binDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        MockURLProtocol.releaseJSON = Data(#"{"tag_name": "2024.01.01"}"#.utf8)

        let updater = YtdlpUpdater(ytdlpURL: ytdlpURL, binDirectory: binDir)
        let result = try await updater.updateIfNeeded(urlSession: mockSession())

        #expect(result == nil)
    }

    @Test func downloadsAndVerifiesChecksumThenWritesExecutableFile() async throws {
        let ytdlpURL = try fakeYtdlpURL(version: "2024.01.01")
        let binDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let assetData = Data("fake yt-dlp binary contents".utf8)

        MockURLProtocol.releaseJSON = Data(#"{"tag_name": "2024.02.02"}"#.utf8)
        MockURLProtocol.assetData = assetData
        MockURLProtocol.checksumsData = Data("\(sha256Hex(assetData))  yt-dlp_macos\n".utf8)

        let updater = YtdlpUpdater(ytdlpURL: ytdlpURL, binDirectory: binDir)
        let result = try await updater.updateIfNeeded(urlSession: mockSession())

        #expect(result == "2024.02.02")
        let binPath = binDir.appendingPathComponent("yt-dlp")
        #expect(try Data(contentsOf: binPath) == assetData)
        let permissions = try FileManager.default.attributesOfItem(atPath: binPath.path)[.posixPermissions] as? Int
        #expect(permissions == 0o755)
    }

    @Test func throwsChecksumMismatchAndDoesNotInstallWhenHashesDiffer() async throws {
        let ytdlpURL = try fakeYtdlpURL(version: "2024.01.01")
        let binDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)

        MockURLProtocol.releaseJSON = Data(#"{"tag_name": "2024.02.02"}"#.utf8)
        MockURLProtocol.assetData = Data("fake yt-dlp binary contents".utf8)
        MockURLProtocol.checksumsData = Data("0000000000000000000000000000000000000000000000000000000000000000  yt-dlp_macos\n".utf8)

        let updater = YtdlpUpdater(ytdlpURL: ytdlpURL, binDirectory: binDir)

        await #expect(throws: YtdlpUpdaterError.checksumMismatch) {
            try await updater.updateIfNeeded(urlSession: mockSession())
        }
        #expect(!FileManager.default.fileExists(atPath: binDir.appendingPathComponent("yt-dlp").path))
    }

    @Test func throwsChecksumMissingWhenSumsFileHasNoMatchingLine() async throws {
        let ytdlpURL = try fakeYtdlpURL(version: "2024.01.01")
        let binDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)

        MockURLProtocol.releaseJSON = Data(#"{"tag_name": "2024.02.02"}"#.utf8)
        MockURLProtocol.assetData = Data("fake yt-dlp binary contents".utf8)
        MockURLProtocol.checksumsData = Data("deadbeef  some-other-asset\n".utf8)

        let updater = YtdlpUpdater(ytdlpURL: ytdlpURL, binDirectory: binDir)

        await #expect(throws: YtdlpUpdaterError.checksumMissing) {
            try await updater.updateIfNeeded(urlSession: mockSession())
        }
    }
}
