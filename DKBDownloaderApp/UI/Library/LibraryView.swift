import DKBDownloaderCore
import SwiftUI

@MainActor
private func statusLabel(_ status: DownloadStatus) -> String {
    switch status {
    // Queued rows are filtered out of this list (they live in Queue until
    // they start), but the switch still has to cover the case.
    case .queued: return t("queue.waiting")
    case .downloading: return t("library.status.downloading")
    case .completed: return t("library.status.completed")
    case .error: return t("library.status.error")
    case .canceled: return t("library.status.canceled")
    }
}

private func statusColor(_ status: DownloadStatus) -> Color {
    switch status {
    case .queued: return .secondary
    case .downloading: return .secondary
    case .completed: return .green
    case .error: return .red
    case .canceled: return .secondary
    }
}

struct LibraryView: View {
    @State private var viewModel = LibraryViewModel()
    @Bindable private var navigation = AppNavigationState.shared
    @State private var pendingDeleteDownload: Download?
    @State private var pendingDeleteRecent: UrlHistoryEntry?
    @State private var showClearRecentConfirm = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage).foregroundStyle(.red).font(.callout).padding([.horizontal, .top])
            }

            switch viewModel.tab {
            case .downloads: downloadsTab
            case .recent: recentTab
            }
        }
        .task { viewModel.start() }
        // A real `.toolbar` (merges into the window's title bar chrome and
        // picks up the Liquid Glass toolbar material on macOS 26+ for free)
        // instead of a Picker floating in the content area.
        //
        // `.toolbar` content is collected from every view in the tree via a
        // preference key, not gated by that view's own visibility/opacity —
        // now that ContentView keeps all four tabs mounted at once (so their
        // state survives a sidebar switch), this view's toolbar would keep
        // contributing even while another tab is on screen unless it's
        // explicitly guarded by whether Library is the active tab.
        .toolbar {
            if navigation.selectedSection == .library {
                ToolbarItemGroup(placement: .automatic) {
                    Picker("", selection: $viewModel.tab) {
                        Text(t("library.tabDownloads")).tag(LibraryViewModel.Tab.downloads)
                        Text(t("library.tabRecent")).tag(LibraryViewModel.Tab.recent)
                    }
                    .pickerStyle(.segmented)
                }

                // Without this, macOS 26's Liquid Glass toolbar fuses the
                // segmented Picker above with the search field/Clear button
                // below into one shared glass container even though they're
                // separate `ToolbarItemGroup`s — the same merging DKB Monitor
                // documented and worked around with this exact API.
                if #available(macOS 26.0, *) {
                    ToolbarSpacer(.fixed, placement: .automatic)
                }

                if viewModel.tab == .recent {
                    ToolbarItemGroup(placement: .automatic) {
                        NativeSearchField(text: $viewModel.recentSearch, placeholder: t("library.recentSearchPlaceholder"))
                            .frame(width: 200)
                        if !viewModel.recentLinks.isEmpty {
                            // Still a plain, unstyled `Button` — its native pill
                            // chrome comes from the system, not from us — just
                            // padding the label text itself so a short word like
                            // "Clear all" isn't cramped against the pill's edges.
                            Button { showClearRecentConfirm = true } label: {
                                Text(t("library.recentClear")).padding(.horizontal, 4)
                            }
                        }
                    }
                }
            }
        }
        .confirmationDialog(
            t("library.deleteDownloadConfirmTitle"),
            isPresented: Binding(
                get: { pendingDeleteDownload != nil },
                set: { if !$0 { pendingDeleteDownload = nil } }
            )
        ) {
            Button(t("library.delete"), role: .destructive) {
                if let record = pendingDeleteDownload {
                    viewModel.delete(record.id ?? -1, deleteFile: false)
                }
                pendingDeleteDownload = nil
            }
        }
        .confirmationDialog(
            t("library.deleteRecentConfirmTitle"),
            isPresented: Binding(
                get: { pendingDeleteRecent != nil },
                set: { if !$0 { pendingDeleteRecent = nil } }
            )
        ) {
            Button(t("library.delete"), role: .destructive) {
                if let entry = pendingDeleteRecent {
                    viewModel.deleteRecent(entry.id ?? -1)
                }
                pendingDeleteRecent = nil
            }
        }
        .confirmationDialog(
            t("library.recentClearConfirmTitle"),
            isPresented: $showClearRecentConfirm
        ) {
            Button(t("library.recentClear"), role: .destructive) { viewModel.clearRecent() }
        }
    }

    @ViewBuilder
    private var downloadsTab: some View {
        if viewModel.records.isEmpty {
            Text(t("library.empty")).foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List(viewModel.records) { record in
                downloadRow(record)
            }
            .listStyle(.inset)
        }
    }

    private func downloadRow(_ record: Download) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(record.title).font(.callout).lineLimit(1)
                Text(record.createdAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption).foregroundStyle(.secondary)
                if record.status == .error, let message = record.errorMessage {
                    // Core writes a language-neutral marker for the
                    // "interrupted by a crash/quit" case; everything else is
                    // yt-dlp's own stderr, which has no translation to give.
                    let shown = message == DownloadRepository.interruptedErrorMessage ? t("library.status.interruptedHint") : message
                    // One line keeps the row compact; the full reason (a
                    // filesystem error can run long) is a hover away.
                    Text(shown).font(.caption).foregroundStyle(.red).lineLimit(1).help(shown)
                }
            }
            Spacer()
            Text(statusLabel(record.status))
                .font(.caption.bold())
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(statusColor(record.status).opacity(0.15), in: Capsule())
                .foregroundStyle(statusColor(record.status))

            if record.status == .completed, let path = record.outputPath {
                Button { viewModel.open(path) } label: { Image(systemName: "play.fill") }
                    .buttonStyle(.plain)
                    .accessibilityLabel(t("library.play"))
                Button { viewModel.reveal(path) } label: { Image(systemName: "folder") }
                    .buttonStyle(.plain)
                    .accessibilityLabel(t("library.reveal"))
            }
            // Everything a retry needs (url, format, folder) is already on the
            // row, so a failed or cancelled download doesn't have to be set up
            // again by hand.
            if record.status == .error || record.status == .canceled {
                Button { viewModel.retry(record) } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.plain)
                    .accessibilityLabel(t("library.retry"))
            }
            Button { pendingDeleteDownload = record } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.plain)
            .accessibilityLabel(t("library.delete"))
        }
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private var recentTab: some View {
        if viewModel.filteredRecent.isEmpty {
            Text(t("library.recentEmpty")).foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List(viewModel.filteredRecent) { entry in
                recentRow(entry)
            }
            .listStyle(.inset)
        }
    }

    private func recentRow(_ entry: UrlHistoryEntry) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.title).font(.callout).lineLimit(1)
                Text(
                    entry.lastFetchedAt.formatted(date: .abbreviated, time: .shortened)
                        + (entry.fetchCount > 1 ? " · " + t("library.recentFetchCount", ["count": "\(entry.fetchCount)"]) : "")
                )
                .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button { viewModel.refetch(entry.url) } label: { Image(systemName: "arrow.clockwise") }
                .buttonStyle(.plain)
                .accessibilityLabel(t("library.refetch"))
            Button { pendingDeleteRecent = entry } label: { Image(systemName: "trash") }
                .buttonStyle(.plain)
                .accessibilityLabel(t("library.delete"))
        }
        .padding(.vertical, 6)
    }
}
