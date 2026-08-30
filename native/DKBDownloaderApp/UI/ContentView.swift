import SwiftUI

/// Sidebar shell — Home (Phase 8) + Queue/Library/Watch (Phase 9). Settings
/// lives in its own `Settings {}` scene (Cmd+,), not in the sidebar.
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
            }
        }
        .frame(minWidth: 700, minHeight: 420)
    }
}
