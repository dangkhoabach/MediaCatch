import Testing
@testable import MediaCatchCore

struct PlaylistEntryTests {
    @Test func mapsEntriesWithUrlAndFallsBackTitleToId() {
        let dump = YtDlpPlaylistDump(
            title: "My Channel",
            entries: [
                YtDlpPlaylistEntry(id: "v1", title: "First video", url: "https://x.com/v1"),
                YtDlpPlaylistEntry(id: "v2", title: nil, url: "https://x.com/v2"),
            ]
        )

        let entries = dump.asPlaylistEntries()

        #expect(entries == [
            PlaylistEntry(title: "First video", url: "https://x.com/v1"),
            PlaylistEntry(title: "v2", url: "https://x.com/v2"),
        ])
    }

    @Test func skipsEntriesWithoutAUrl() {
        let dump = YtDlpPlaylistDump(
            title: nil,
            entries: [YtDlpPlaylistEntry(id: "v1", title: "no url", url: nil)]
        )
        #expect(dump.asPlaylistEntries().isEmpty)
    }
}
