import Foundation
import Testing
@testable import DKBDownloaderCore

struct VideoInfoTests {
    @Test func decodesAndMapsHasVideoHasAudioFromCodecs() throws {
        let json = """
        {
            "id": "abc123",
            "title": "A video",
            "thumbnail": "https://example.com/thumb.jpg",
            "duration": 125.5,
            "formats": [
                {"format_id": "137", "ext": "mp4", "height": 1080, "vcodec": "avc1", "acodec": "none", "filesize": 1000},
                {"format_id": "140", "ext": "m4a", "vcodec": "none", "acodec": "mp4a", "filesize_approx": 500},
                {"format_id": "18", "ext": "mp4", "height": 360, "vcodec": "avc1", "acodec": "mp4a"}
            ]
        }
        """
        let info = YtDlpInfo.self
        let decoded = try JSONDecoder().decode(info, from: Data(json.utf8))
        let videoInfo = VideoInfo(decoded)

        #expect(videoInfo.id == "abc123")
        #expect(videoInfo.formats.count == 3)

        let videoOnly = videoInfo.formats[0]
        #expect(videoOnly.hasVideo && !videoOnly.hasAudio)
        #expect(videoOnly.filesize == 1000)

        let audioOnly = videoInfo.formats[1]
        #expect(!audioOnly.hasVideo && audioOnly.hasAudio)
        #expect(audioOnly.filesize == 500, "must fall back to filesize_approx when filesize is missing")

        let both = videoInfo.formats[2]
        #expect(both.hasVideo && both.hasAudio)
    }

    @Test func missingFormatsFieldDecodesToEmptyArray() throws {
        let json = """
        {"id": "x", "title": "no formats"}
        """
        let decoded = try JSONDecoder().decode(YtDlpInfo.self, from: Data(json.utf8))
        #expect(VideoInfo(decoded).formats.isEmpty)
    }
}
