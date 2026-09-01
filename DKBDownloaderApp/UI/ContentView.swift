import SwiftUI

/// Sidebar shell — Home/Queue/Library/Watch (Phase 8-9) + Settings as its own
/// sidebar tab. Settings used to live in a separate `Settings {}` scene
/// (its own floating window on Cmd+,); the app menu's Cmd+, and the menu bar
/// tray's "Settings…" item both now just bring this window forward and
/// select this same tab instead, so there's exactly one Settings surface
/// regardless of entry point.
struct ContentView: View {
    @Bindable private var navigation = AppNavigationState.shared
    @FocusState private var sidebarFocused: Bool

    var body: some View {
        NavigationSplitView {
            List(SidebarSection.allCases, selection: $navigation.selectedSection) { section in
                // Every row's icon rendered accent-blue regardless of
                // selection — the pill highlight was the only thing marking
                // the current tab. Dimming unselected icons to `.secondary`
                // (via the icon-only closure, so the label text's own color
                // is untouched) makes the selected one read as "lit up"
                // against them. The selected row itself is left un-tinted
                // here — its pill background is already solid accent color,
                // so forcing the icon to that same blue made it blend into
                // its own background; leaving it alone lets the system give
                // it the same white-on-accent treatment the row's text gets.
                Label {
                    Text(section.label)
                } icon: {
                    Image(systemName: section.systemImage)
                        .foregroundStyle(section == navigation.selectedSection ? Color.primary : Color.secondary)
                }
                .tag(section)
            }
            .navigationSplitViewColumnWidth(min: 160, ideal: 180)
            .focused($sidebarFocused)
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
        .onAppear { sidebarFocused = true }
        // Swapping the detail view (any sidebar click that actually changes
        // tabs) seems to drop first-responder status back off the sidebar's
        // List even though the window stays key — the pill then renders in
        // its "inactive window" gray style instead of accent blue, though
        // clicking blank sidebar space (no tab switch) keeps it blue. Explicit
        // `@FocusState` re-assigned right after every switch reclaims focus
        // for the sidebar instead of leaving it wherever the detail swap left it.
        .onChange(of: navigation.selectedSection) { _, _ in sidebarFocused = true }
    }
}
