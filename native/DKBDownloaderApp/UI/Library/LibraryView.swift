import DKBDownloaderCore
import SwiftUI

@MainActor
private func statusLabel(_ status: DownloadStatus) -> String {
    switch status {
    case .downloading: return t("library.status.downloading")
    case .completed: return t("library.status.completed")
    case .error: return t("library.status.error")
    case .canceled: return t("library.status.canceled")
    }
}

private func statusColor(_ status: DownloadStatus) -> Color {
    switch status {
    case .downloading: return .secondary
    case .completed: return .green
    case .error: return .red
    case .canceled: return .secondary
    }
}

struct LibraryView: View {
    @State private var viewModel = LibraryViewModel()

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
        .toolbar {
            ToolbarItemGroup(placement: .automatic) {
                Picker("", selection: $viewModel.tab) {
                    Text(t("library.tabDownloads")).tag(LibraryViewModel.Tab.downloads)
                    Text(t("library.tabRecent")).tag(LibraryViewModel.Tab.recent)
                }
                .pickerStyle(.segmented)

                if viewModel.tab == .recent {
                    NativeSearchField(text: $viewModel.recentSearch, placeholder: t("library.recentSearchPlaceholder"))
                        .frame(width: 200)
                    if !viewModel.recentLinks.isEmpty {
                        Button(t("library.recentClear")) { viewModel.clearRecent() }
                    }
                }
            }
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
                    Text(message).font(.caption).foregroundStyle(.red).lineLimit(1)
                }
            }
            Spacer()
            Text(statusLabel(record.status))
                .font(.caption.bold())
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(statusColor(record.status).opacity(0.15), in: Capsule())
                .foregroundStyle(statusColor(record.status))

            if record.status == .completed, let path = record.outputPath {
                Button { viewModel.open(path) } label: { Image(systemName: "play.fill") }.buttonStyle(.plain)
                Button { viewModel.reveal(path) } label: { Image(systemName: "folder") }.buttonStyle(.plain)
            }
            Button { viewModel.delete(record.id ?? -1, deleteFile: false) } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.plain)
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
            Button { viewModel.refetch(entry.url) } label: { Image(systemName: "arrow.clockwise") }.buttonStyle(.plain)
            Button { viewModel.deleteRecent(entry.id ?? -1) } label: { Image(systemName: "trash") }.buttonStyle(.plain)
        }
        .padding(.vertical, 6)
    }
}
