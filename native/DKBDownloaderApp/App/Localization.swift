import Observation
import SwiftUI

enum AppLocale: String {
    case en, vi

    /// Falls back to the system's language exactly once, on first launch —
    /// mirrors `context.tsx::detectDefaultLocale`'s `navigator.language`
    /// check — before the user ever picks a value in Settings.
    static var systemDefault: AppLocale {
        Locale.current.language.languageCode?.identifier == "vi" ? .vi : .en
    }
}

/// D14: unlike the rest of the app's system-following behavior, language is
/// a manual toggle independent of System Settings > Language & Region —
/// stored here (not `@AppStorage` in every view) so every view that calls
/// `t()` re-renders the instant Settings changes it, without needing its own
/// `@AppStorage` property just to observe the same key. Same singleton shape
/// as `AppNavigationState`/`DownloadEventCenter`.
@Observable
@MainActor
final class LocalizationCenter {
    static let shared = LocalizationCenter()

    private static let storageKey = "dkb-downloader:locale"

    var locale: AppLocale {
        didSet { UserDefaults.standard.set(locale.rawValue, forKey: Self.storageKey) }
    }

    private init() {
        let stored = UserDefaults.standard.string(forKey: Self.storageKey).flatMap(AppLocale.init(rawValue:))
        locale = stored ?? .systemDefault
    }
}

/// Looks up `key` in `Localizable.xcstrings` against `LocalizationCenter`'s
/// locale (not the system's) and substitutes `{name}`-style placeholders —
/// mirrors `context.tsx`'s `t()` exactly, including the placeholder syntax.
@MainActor
func t(_ key: String, _ vars: [String: String] = [:]) -> String {
    var result = String(
        localized: String.LocalizationValue(stringLiteral: key),
        locale: Locale(identifier: LocalizationCenter.shared.locale.rawValue)
    )
    for (name, value) in vars {
        result = result.replacingOccurrences(of: "{\(name)}", with: value)
    }
    return result
}
