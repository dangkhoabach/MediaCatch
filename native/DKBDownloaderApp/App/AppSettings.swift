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
}
