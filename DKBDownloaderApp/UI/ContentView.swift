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
            // Home/Queue/Library/Watch stay mounted permanently (ZStack +
            // opacity, not a `switch`) instead of being torn down and
            // recreated every time the sidebar selection changes — a
            // `switch` drops the non-selected case's view (and its
            // `@State private var viewModel`) from the tree entirely, so a
            // Home fetch in progress (or Watch's typed-but-unsubmitted URL,
            // Library's search text) reset to empty the moment you switched
            // away and back. Keeping them alive also lets Queue/Library's
            // background poll loops (`.task { viewModel.start() }`) keep
            // running while another tab is in front. Settings is layered on
            // top instead of replacing the other four: it's pure
            // `@AppStorage`, nothing transient to lose, so recreating it
            // lazily via `if` is simpler and free — but it must overlay
            // rather than swap out, or switching to Settings and back would
            // tear the other four down all the same.
            ZStack {
                HomeView()
                    .opacity(navigation.selectedSection == .home ? 1 : 0)
                    .allowsHitTesting(navigation.selectedSection == .home)
                QueueView()
                    .opacity(navigation.selectedSection == .queue ? 1 : 0)
                    .allowsHitTesting(navigation.selectedSection == .queue)
                LibraryView()
                    .opacity(navigation.selectedSection == .library ? 1 : 0)
                    .allowsHitTesting(navigation.selectedSection == .library)
                WatchView()
                    .opacity(navigation.selectedSection == .watch ? 1 : 0)
                    .allowsHitTesting(navigation.selectedSection == .watch)
                if navigation.selectedSection == .settings {
                    SettingsView()
                }
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
