import DKBDownloaderCore
import SwiftUI

struct QueueView: View {
    @State private var viewModel = QueueViewModel()
    private var eventCenter: DownloadEventCenter { DownloadEventCenter.shared }

    var body: some View {
        Group {
            if viewModel.downloads.isEmpty {
                Text(t("queue.empty"))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // A real `List` (not a hand-rolled `ScrollView`/`VStack`) so
                // rows get the system's native background/hover/separator
                // chrome — and, on macOS 26+, the Liquid Glass sidebar/list
                // material automatically, with no styling of our own.
                List(viewModel.downloads) { download in
                    row(download)
                }
                .listStyle(.inset)
            }
        }
        .task { viewModel.start() }
    }

    private func percent(from progress: DownloadProgress?) -> Double {
        guard let progress else { return 0 }
        let cleaned = progress.percent
            .trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: "%", with: "")
            .replacingOccurrences(of: ",", with: ".")
        return Double(cleaned) ?? 0
    }

    @ViewBuilder
    private func row(_ download: Download) -> some View {
        let id = download.id ?? -1
        let progress = eventCenter.progressById[id]
        let isQueued = download.status == .queued

        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(download.title).font(.callout).lineLimit(1)
                Spacer()
                // Nothing to pause until it has actually started — the button
                // would be a permanent no-op on a queued row.
                if !isQueued {
                    Button {
                        Task { await viewModel.togglePause(id) }
                    } label: {
                        Image(systemName: viewModel.isPaused(id) ? "play.fill" : "pause.fill")
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(viewModel.isPaused(id) ? t("queue.resume") : t("queue.pause"))
                }
                Button {
                    Task { await viewModel.cancel(id) }
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.plain)
                .accessibilityLabel(t("queue.cancel"))
            }

            if isQueued {
                // A determinate 0% bar would read as "started but stuck".
                Text(t("queue.waiting")).font(.caption).foregroundStyle(.secondary)
            } else {
                ProgressView(value: percent(from: progress), total: 100)
                HStack {
                    Text(progress?.percent.trimmingCharacters(in: .whitespaces) ?? "0%")
                    Spacer()
                    Text(progress?.speed.trimmingCharacters(in: .whitespaces) ?? "")
                    Spacer()
                    if let eta = progress?.eta.trimmingCharacters(in: .whitespaces), !eta.isEmpty {
                        Text(t("queue.eta", ["eta": eta]))
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 6)
    }
}
