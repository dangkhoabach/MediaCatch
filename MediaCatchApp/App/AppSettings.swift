import Foundation

/// Plain `UserDefaults`-backed settings storage — mirrors `settings.ts`'s
/// localStorage keys/defaults exactly. The Settings UI reads and writes
/// through these same functions; Home only needs the read side (with
/// sensible defaults).
enum AppSettings {
    // UserDefaults is documented by Apple as thread-safe; Swift 6 just can't
    // verify that itself since the type predates Sendable.
    private nonisolated(unsafe) static let defaults = UserDefaults.standard

    private enum Keys {
        static let outputDir = "dkb-downloader:outputDir"
        static let outputFormat = "dkb-downloader:outputFormat"
        static let embedMetadata = "dkb-downloader:embedMetadata"
        static let cookiesBrowser = "dkb-downloader:cookiesBrowser"
        static let cookiesFile = "dkb-downloader:cookiesFile"
        static let useAria2c = "dkb-downloader:useAria2c"
        static let notificationsEnabled = "dkb-downloader:notificationsEnabled"
        static let maxConcurrentDownloads = "dkb-downloader:maxConcurrentDownloads"
        static let clipboardSuggestions = "dkb-downloader:clipboardSuggestions"
        static let rateLimitMBs = "dkb-downloader:rateLimitMBs"
        static let subtitleLanguages = "dkb-downloader:subtitleLanguages"
    }

    /// Falls back to the OS Downloads folder and persists it the first time
    /// the app runs — mirrors `settings.ts::ensureOutputDir`.
    static func ensureOutputDir() -> String {
        if let current = defaults.string(forKey: Keys.outputDir), !current.isEmpty {
            return current
        }
        let fallback = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0].path
        defaults.set(fallback, forKey: Keys.outputDir)
        return fallback
    }

    /// Why the download folder can't take a finished file right now.
    enum OutputDirProblem: Equatable {
        /// macOS (TCC) refused the write — the user clicked "Don't Allow" on
        /// the Downloads/Desktop/Documents prompt, or the grant was lost.
        /// Only System Settings › Privacy & Security › Files and Folders can
        /// undo that; the app can't re-ask.
        case accessDenied
        /// The folder lives on an external drive that isn't mounted. Kept
        /// apart from `accessDenied` because creating anything under the
        /// root-owned `/Volumes` also fails with EACCES, and "open System
        /// Settings" would be the wrong advice for a drive that's unplugged.
        case volumeMissing
        /// Anything else, with the filesystem's own wording.
        case unreachable(String)
    }

    /// Probes the folder the way a finished download will: creates it if it
    /// went missing, then writes and removes a marker file. Cheap, and worth
    /// running before a download rather than after — the move at the end
    /// used to be the first time anyone found out the folder was unusable,
    /// by which point the file had already been downloaded. Blocks while
    /// macOS shows its folder-access prompt, so call it off the main thread.
    static func outputDirProblem(_ path: String) -> OutputDirProblem? {
        let fm = FileManager.default
        let components = URL(fileURLWithPath: path).pathComponents  // ["/", "Volumes", "<name>", ...]
        if components.count > 2, components[1] == "Volumes", !fm.fileExists(atPath: "/Volumes/" + components[2]) {
            return .volumeMissing
        }
        let marker = URL(fileURLWithPath: path).appendingPathComponent(".dkb-downloader-write-test")
        do {
            try fm.createDirectory(atPath: path, withIntermediateDirectories: true)
            try Data().write(to: marker)
            try? fm.removeItem(at: marker)
            return nil
        } catch {
            return isPermissionDenied(error) ? .accessDenied : .unreachable(error.localizedDescription)
        }
    }

    /// Foundation wraps the POSIX EPERM/EACCES from a TCC refusal in a Cocoa
    /// "no permission" error, so both layers are checked.
    private static func isPermissionDenied(_ error: Error) -> Bool {
        let nsError = error as NSError
        if nsError.domain == NSCocoaErrorDomain,
           nsError.code == NSFileWriteNoPermissionError || nsError.code == NSFileReadNoPermissionError {
            return true
        }
        if nsError.domain == NSPOSIXErrorDomain, nsError.code == EPERM || nsError.code == EACCES {
            return true
        }
        if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? Error {
            return isPermissionDenied(underlying)
        }
        return false
    }

    static func outputFormat() -> String {
        defaults.string(forKey: Keys.outputFormat) ?? "mp4"
    }

    /// Off by default — embedding subs/chapters/thumbnail adds post-processing time.
    static func embedMetadata() -> Bool {
        defaults.bool(forKey: Keys.embedMetadata)
    }

    /// `nil` means "don't read any browser's cookies" — omit the yt-dlp arg
    /// entirely rather than pass the literal string "none".
    static func cookiesBrowser() -> String? {
        let value = defaults.string(forKey: Keys.cookiesBrowser)
        return (value == nil || value == "none") ? nil : value
    }

    /// An exported cookies.txt, used instead of reading a browser's store.
    ///
    /// A path that no longer resolves is treated as unset. Handing it to
    /// yt-dlp anyway isn't an error — verified against 2026.08.19, which just
    /// carries on without cookies. It doesn't even warn: re-checked with
    /// warnings fully enabled, the way fetches now run, and it says nothing at
    /// all. So this check is the only thing standing between the user and a
    /// setting that silently stopped working; Settings flags the broken path.
    static func cookiesFile() -> String? {
        guard let path = defaults.string(forKey: Keys.cookiesFile), !path.isEmpty,
              FileManager.default.fileExists(atPath: path)
        else { return nil }
        return path
    }

    /// Off by default — requires the user to have aria2c installed separately.
    static func useAria2c() -> Bool {
        defaults.bool(forKey: Keys.useAria2c)
    }

    /// How many downloads run at once; the rest wait in `DownloadManager`'s
    /// queue. 3 by default — enough to keep the link saturated without
    /// splitting it so many ways that every download crawls. Absent means
    /// "never set", not `Bool`-style zero.
    static func maxConcurrentDownloads() -> Int {
        let stored = defaults.integer(forKey: Keys.maxConcurrentDownloads)
        return stored > 0 ? stored : 3
    }

    /// A yt-dlp rate string ("5M"), or `nil` for no cap — 0/absent means
    /// unlimited, which is the default.
    static func rateLimit() -> String? {
        let megabytesPerSecond = defaults.integer(forKey: Keys.rateLimitMBs)
        return megabytesPerSecond > 0 ? "\(megabytesPerSecond)M" : nil
    }

    /// Only used when metadata embedding is on, which is what pulls subtitles
    /// in at all. Empty falls back to the previous hardcoded pair.
    static func subtitleLanguages() -> String {
        let stored = defaults.string(forKey: Keys.subtitleLanguages)?.trimmingCharacters(in: .whitespaces)
        return (stored?.isEmpty == false ? stored : nil) ?? "en,vi"
    }

    /// On by default — it's the point of the feature, and it only ever fills
    /// an empty URL field with a full http(s) link; nothing is fetched until
    /// the user presses Fetch. Absent means "never set", not `Bool`'s zero.
    static func clipboardSuggestions() -> Bool {
        defaults.object(forKey: Keys.clipboardSuggestions) == nil ? true : defaults.bool(forKey: Keys.clipboardSuggestions)
    }

    /// On by default (mirrors `settings.ts::getNotificationsEnabled`'s
    /// `!== "false"` — absent means "on", not "off" like `Bool`'s zero value).
    static func notificationsEnabled() -> Bool {
        defaults.object(forKey: Keys.notificationsEnabled) == nil ? true : defaults.bool(forKey: Keys.notificationsEnabled)
    }
}
