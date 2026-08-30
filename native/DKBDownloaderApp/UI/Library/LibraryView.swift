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
        VStack(alignment: .leading, spacing: 12) {
            Picker("", selection: $viewModel.tab) {
                Text(t("library.tabDownloads")).tag(LibraryViewModel.Tab.downloads)
                Text(t("library.tabRecent")).tag(LibraryViewModel.Tab.recent)
            }
            .pickerStyle(.segmented)
            .frame(width: 260)

            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage).foregroundStyle(.red).font(.callout)
            }

            switch viewModel.tab {
            case .downloads: downloadsTab
            case .recent: recentTab
            }
        }
        .padding(20)
        .task { viewModel.start() }
    }

    @ViewBuilder
    private var downloadsTab: some View {
        if viewModel.records.isEmpty {
            Text(t("library.empty")).foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(viewModel.records) { record in
                        downloadRow(record)
                    }
                }
            }
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
                .font(.caption).foregroundStyle(statusColor(record.status))
                .padding(.horizontal, 8).padding(.vertical, 2)
                .background(Capsule().strokeBorder(statusColor(record.status)))

            if record.status == .completed, let path = record.outputPath {
                Button { viewModel.open(path) } label: { Image(systemName: "play.fill") }.buttonStyle(.plain)
                Button { viewModel.reveal(path) } label: { Image(systemName: "folder") }.buttonStyle(.plain)
            }
            Button { viewModel.delete(record.id ?? -1, deleteFile: false) } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.plain)
        }
        .padding(10)
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.separator))
    }

    @ViewBuilder
    private var recentTab: some View {
        HStack {
            TextField(t("library.recentSearchPlaceholder"), text: $viewModel.recentSearch)
                .textFieldStyle(.roundedBorder)
            if !viewModel.recentLinks.isEmpty {
                Button(t("library.recentClear")) { viewModel.clearRecent() }
            }
        }

        if viewModel.filteredRecent.isEmpty {
            Text(t("library.recentEmpty")).foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(viewModel.filteredRecent) { entry in
                        recentRow(entry)
                    }
                }
            }
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
        .padding(10)
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.separator))
    }
}
