import Observation

enum SidebarSection: String, CaseIterable, Identifiable {
    case home, queue, library, watch, settings
    var id: String { rawValue }

    @MainActor
    var label: String {
        switch self {
        case .home: return t("nav.home")
        case .queue: return t("nav.queue")
        case .library: return t("nav.library")
        case .watch: return t("nav.watch")
        case .settings: return t("nav.settings")
        }
    }

    var systemImage: String {
        switch self {
        case .home: return "link"
        case .queue: return "arrow.down.circle"
        case .library: return "square.stack"
        case .watch: return "eye"
        case .settings: return "gearshape"
        }
    }
}

/// Cross-section navigation, shared across the sidebar's destinations —
/// mirrors `home-state.tsx`'s `pendingFetchUrl` (Library's "Recent links" →
/// re-fetch on Home) plus the section switch itself, which react-router
/// handled implicitly via routes.
@Observable
@MainActor
final class AppNavigationState {
    static let shared = AppNavigationState()

    var selectedSection: SidebarSection = .home

    /// Set by another section (e.g. Library's "Recent links" tab, Phase 9)
    /// to ask Home to re-fetch a URL as soon as it's visible. Home clears it
    /// once handled.
    var pendingFetchUrl: String?

    private init() {}
}
