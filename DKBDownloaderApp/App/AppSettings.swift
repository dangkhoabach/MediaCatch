import Foundation

/// Plain `UserDefaults`-backed settings storage — mirrors `settings.ts`'s
/// localStorage keys/defaults exactly. Phase 9's Settings UI reads/writes
/// through these same functions; Phase 8 only needs the read side (with
/// sensible defaults) since Home starts a download before Settings exists.
enum AppSettings {
    // UserDefaults is documented by Apple as thread-safe; Swift 6 just can't
    // verify that itself since the type predates Sendable.
    private nonisolated(unsafe) static let defaults = UserDefaults.standard

    private enum Keys {
        static let outputDir = "dkb-downloader:outputDir"
        static let outputFormat = "dkb-downloader:outputFormat"
        static let embedMetadata = "dkb-downloader:embedMetadata"
        static let cookiesBrowser = "dkb-downloader:cookiesBrowser"
        static let useAria2c = "dkb-downloader:useAria2c"
        static let notificationsEnabled = "dkb-downloader:notificationsEnabled"
        static let maxConcurrentDownloads = "dkb-downloader:maxConcurrentDownloads"
        static let clipboardSuggestions = "dkb-downloader:clipboardSuggestions"
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
