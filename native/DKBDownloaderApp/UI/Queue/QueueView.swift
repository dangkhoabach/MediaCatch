import DKBDownloaderCore
import SwiftUI

struct QueueView: View {
    @State private var viewModel = QueueViewModel()
    private var eventCenter: DownloadEventCenter { DownloadEventCenter.shared }

    var body: some View {
        Group {
            if viewModel.downloads.isEmpty {
                Text("No active downloads")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(viewModel.downloads) { download in
                            row(download)
                        }
                    }
                    .padding(20)
                }
            }
        }
        .task { viewModel.start() }
    }

    private func percent(from progress: DownloadProgress?) -> Double {
        guard let progress else { return 0 }
        let digits = progress.percent.filter { $0.isNumber || $0 == "." }
        return Double(digits) ?? 0
    }

    @ViewBuilder
    private func row(_ download: Download) -> some View {
        let id = download.id ?? -1
        let progress = eventCenter.progressById[id]

        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(download.title).font(.callout).lineLimit(1)
                Spacer()
                Button {
                    Task { await viewModel.togglePause(id) }
                } label: {
                    Image(systemName: viewModel.isPaused(id) ? "play.fill" : "pause.fill")
                }
                .buttonStyle(.plain)
                Button {
                    Task { await viewModel.cancel(id) }
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.plain)
            }
            ProgressView(value: percent(from: progress), total: 100)
            HStack {
                Text(progress?.percent.trimmingCharacters(in: .whitespaces) ?? "0%")
                Spacer()
                Text(progress?.speed.trimmingCharacters(in: .whitespaces) ?? "")
                Spacer()
                if let eta = progress?.eta.trimmingCharacters(in: .whitespaces), !eta.isEmpty {
                    Text("ETA \(eta)")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(10)
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.separator))
    }
}
