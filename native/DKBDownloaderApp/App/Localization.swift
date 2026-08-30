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
///
/// `String(localized:locale:)` was tried first and silently ignored its
/// `locale:` argument here — verified independently outside SwiftUI (a
/// throwaway script loading the built .app's bundle) that it kept returning
/// the process's system-language string for every explicit `locale:` value,
/// while the legacy `Bundle.localizedString(forKey:)` against the matching
/// `.lproj` sub-bundle returned the correct, different string every time.
/// That's why Settings' language picker had no visible effect. Looking the
/// `.lproj` bundle up by hand and using the old API sidesteps whatever that
/// mismatch is.
@MainActor
func t(_ key: String, _ vars: [String: String] = [:]) -> String {
    let localeId = LocalizationCenter.shared.locale.rawValue
    let localeBundle: Bundle
    if let path = Bundle.main.path(forResource: localeId, ofType: "lproj"), let bundle = Bundle(path: path) {
        localeBundle = bundle
    } else {
        localeBundle = .main
    }
    var result = localeBundle.localizedString(forKey: key, value: nil, table: "Localizable")
    for (name, value) in vars {
        result = result.replacingOccurrences(of: "{\(name)}", with: value)
    }
    return result
}
