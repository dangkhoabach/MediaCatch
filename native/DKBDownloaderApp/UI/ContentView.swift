import SwiftUI

/// Sidebar shell (Phase 8) — Home has real content; Queue/Library/Watch are
/// placeholders until Phase 9 builds them, matching the same pattern this
/// file itself used as a whole-window placeholder through Phase 1-7.
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
                Text("Queue — coming in Phase 9").foregroundStyle(.secondary)
            case .library:
                Text("Library — coming in Phase 9").foregroundStyle(.secondary)
            case .watch:
                Text("Watch — coming in Phase 9").foregroundStyle(.secondary)
            }
        }
        .frame(minWidth: 700, minHeight: 420)
    }
}
