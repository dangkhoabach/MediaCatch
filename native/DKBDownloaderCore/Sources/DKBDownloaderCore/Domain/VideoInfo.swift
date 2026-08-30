import Foundation

/// Subset of yt-dlp's `-j` (dump-json) output actually used — mirrors
/// `models.rs::YtDlpInfo`/`YtDlpFormat` field-for-field.
struct YtDlpInfo: Decodable {
    let id: String
    let title: String
    let thumbnail: String?
    let duration: Double?
    let formats: [YtDlpFormat]?
}

struct YtDlpFormat: Decodable {
    let formatId: String
    let ext: String?
    let height: Int?
    let fps: Double?
    let vcodec: String?
    let acodec: String?
    let filesize: Int64?
    let filesizeApprox: Int64?
    let tbr: Double?
    let formatNote: String?

    enum CodingKeys: String, CodingKey {
        case formatId = "format_id"
        case ext, height, fps, vcodec, acodec, filesize
        case filesizeApprox = "filesize_approx"
        case tbr
        case formatNote = "format_note"
    }
}

public struct VideoFormat: Sendable, Equatable {
    public let formatId: String
    public let ext: String
    public let height: Int?
    public let fps: Double?
    public let vcodec: String
    public let acodec: String
    public let hasVideo: Bool
    public let hasAudio: Bool
    public let filesize: Int64?
    public let tbr: Double?
    public let formatNote: String?

    init(_ format: YtDlpFormat) {
        let vcodec = format.vcodec ?? "none"
        let acodec = format.acodec ?? "none"
        self.formatId = format.formatId
        self.ext = format.ext ?? ""
        self.height = format.height
        self.fps = format.fps
        self.hasVideo = vcodec != "none"
        self.hasAudio = acodec != "none"
        self.vcodec = vcodec
        self.acodec = acodec
        self.filesize = format.filesize ?? format.filesizeApprox
        self.tbr = format.tbr
        self.formatNote = format.formatNote
    }
}

public struct VideoInfo: Sendable, Equatable {
    public let id: String
    public let title: String
    public let thumbnail: String?
    public let duration: Double?
    public let formats: [VideoFormat]

    init(_ info: YtDlpInfo) {
        self.id = info.id
        self.title = info.title
        self.thumbnail = info.thumbnail
        self.duration = info.duration
        self.formats = (info.formats ?? []).map(VideoFormat.init)
    }
}
