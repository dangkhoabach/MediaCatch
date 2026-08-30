import SwiftUI

/// Sidebar shell — Home/Queue/Library/Watch (Phase 8-9) + Settings as its own
/// sidebar tab. Settings used to live in a separate `Settings {}` scene
/// (its own floating window on Cmd+,); the app menu's Cmd+, and the menu bar
/// tray's "Settings…" item both now just bring this window forward and
/// select this same tab instead, so there's exactly one Settings surface
/// regardless of entry point.
struct ContentView: View {
    @Bindable private var navigation = AppNavigationState.shared

    var body: some View {
        NavigationSplitView {
            List(SidebarSection.allCases, selection: $navigation.selectedSection) { section in
                Label(section.label, systemImage: section.systemImage).tag(section)
            }
            .navigationSplitViewColumnWidth(min: 160, ideal: 180)
        } detail: {
            switch navigation.selectedSection {
            case .home:
                HomeView()
            case .queue:
                QueueView()
            case .library:
                LibraryView()
            case .watch:
                WatchView()
            case .settings:
                SettingsView()
            }
        }
        .frame(minWidth: 700, minHeight: 420)
    }
}
