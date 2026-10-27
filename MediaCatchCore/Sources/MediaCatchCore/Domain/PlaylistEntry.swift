import Foundation

/// `yt-dlp -J --flat-playlist` dumps ONE json object for the whole
/// playlist/channel — mirrors `models.rs::YtDlpPlaylistDump`/`YtDlpPlaylistEntry`.
public struct YtDlpPlaylistDump: Decodable, Sendable {
    public let title: String?
    let entries: [YtDlpPlaylistEntry]

    init(title: String?, entries: [YtDlpPlaylistEntry]) {
        self.title = title
        self.entries = entries
    }
}

struct YtDlpPlaylistEntry: Decodable, Sendable {
    let id: String
    let title: String?
    let url: String?
}

/// A single video resolved from `expandPlaylist`, ready to hand to the
/// frontend's batch-mode flow.
public struct PlaylistEntry: Sendable, Equatable {
    public let title: String
    public let url: String

    public init(title: String, url: String) {
        self.title = title
        self.url = url
    }
}

extension YtDlpPlaylistDump {
    /// The channel/playlist's own recent-entry ids, used by watch-polling to
    /// seed "already known" videos — mirrors watch.rs's use of `dump.entries`.
    public var entryIds: [String] {
        entries.map(\.id)
    }

    public func asPlaylistEntries() -> [PlaylistEntry] {
        entries.compactMap { entry in
            guard let url = entry.url else { return nil }
            return PlaylistEntry(title: entry.title ?? entry.id, url: url)
        }
    }
}
