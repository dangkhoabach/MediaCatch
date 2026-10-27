import Foundation

/// Rejects input yt-dlp would read as an option instead of a URL.
///
/// The argument lists already end options with `--`, so such a string can no
/// longer actually be parsed as one — this is the second layer, and what
/// turns a confusing `'--version' is not a valid URL` into a clear message
/// before any process is spawned at all (Home's drag-and-drop fetches
/// whatever was dropped with no confirmation step).
///
/// Deliberately narrow: yt-dlp resolves scheme-less input like
/// `youtu.be/<id>` perfectly well — verified — so requiring an http(s)
/// scheme here would reject links people legitimately paste. Everything that
/// isn't dash-leading keeps going straight through, exactly as before.
func isFetchableURL(_ string: String) -> Bool {
    !string.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("-")
}
