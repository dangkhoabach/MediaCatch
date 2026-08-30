import DKBDownloaderCore
import SwiftUI

private func formatSize(_ bytes: Int64?) -> String {
    guard let bytes, bytes > 0 else { return "—" }
    let mb = Double(bytes) / (1024 * 1024)
    return mb > 1024 ? String(format: "%.2f GB", mb / 1024) : String(format: "%.1f MB", mb)
}

private func formatDuration(_ seconds: Double?) -> String {
    guard let seconds, seconds > 0 else { return "—" }
    let m = Int(seconds) / 60
    let s = Int(seconds) % 60
    return "\(m):\(String(format: "%02d", s))"
}

struct HomeView: View {
    @State private var viewModel = HomeViewModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Spacer()
                    Toggle("Batch mode", isOn: $viewModel.batchMode)
                        .toggleStyle(.switch)
                        .onChange(of: viewModel.batchMode) { _, _ in viewModel.batchItems = [] }
                }

                if let errorMessage = viewModel.errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                        .font(.callout)
                }

                if viewModel.batchMode {
                    batchSection
                } else {
                    fetchSection
                    if let info = viewModel.info {
                        infoSection(info)
                    }
                }
            }
            .padding(24)
        }
        .frame(minWidth: 480, minHeight: 360)
        .task(id: AppNavigationState.shared.pendingFetchUrl) {
            if let pending = AppNavigationState.shared.pendingFetchUrl {
                await viewModel.handlePendingFetch(pending)
            }
        }
    }

    private var fetchSection: some View {
        HStack {
            TextField("Paste a video/playlist URL…", text: $viewModel.url)
                .textFieldStyle(.roundedBorder)
                .onSubmit { Task { await viewModel.fetchInfo() } }
            Button {
                Task { await viewModel.fetchInfo() }
            } label: {
                if viewModel.loading {
                    ProgressView().controlSize(.small)
                } else {
                    Text("Fetch Info")
                }
            }
            .disabled(viewModel.loading || viewModel.url.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    @ViewBuilder
    private func infoSection(_ info: VideoInfo) -> some View {
        let videoFormats = info.formats.filter(\.hasVideo).sorted { ($0.height ?? 0) > ($1.height ?? 0) }
        let imageFormats = info.formats.filter { !$0.hasVideo && !$0.hasAudio }
            .sorted { ($0.filesize ?? 0) > ($1.filesize ?? 0) }
        let audioFormats = info.formats.filter { $0.hasAudio && !$0.hasVideo }
            .sorted { ($0.tbr ?? 0) > ($1.tbr ?? 0) }

        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                if let thumbnail = info.thumbnail, let thumbnailURL = URL(string: thumbnail) {
                    AsyncImage(url: thumbnailURL) { image in
                        image.resizable().aspectRatio(contentMode: .fill)
                    } placeholder: {
                        Color.gray.opacity(0.2)
                    }
                    .frame(width: 160, height: 96)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(info.title).font(.headline)
                        if let platform = viewModel.platform {
                            Text(platform)
                                .font(.caption)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Capsule().strokeBorder())
                        }
                    }
                    Text(formatDuration(info.duration)).font(.caption).foregroundStyle(.secondary)
                }
            }

            if !videoFormats.isEmpty {
                Toggle(isOn: Binding(get: { viewModel.audioOnly }, set: { viewModel.setAudioOnly($0) })) {
                    Label("Audio only", systemImage: "music.note")
                }
                .toggleStyle(.switch)
            }

            if viewModel.audioOnly, !audioFormats.isEmpty {
                formatList(audioFormats) { format in
                    formatRow(icon: "music.note", primary: format.tbr.map { "\(Int($0))kbps" } ?? "—", secondary: format.ext.uppercased(), size: format.filesize, formatId: format.formatId)
                }
            }

            if !viewModel.audioOnly, !videoFormats.isEmpty {
                formatList(videoFormats) { format in
                    formatRow(
                        icon: "video",
                        primary: format.height.map { "\($0)p" } ?? "—",
                        secondary: format.vcodec,
                        size: format.filesize,
                        formatId: format.formatId,
                        trailing: format.hasAudio ? "has audio" : "no audio"
                    )
                }
            }

            if videoFormats.isEmpty, !imageFormats.isEmpty {
                formatList(imageFormats) { format in
                    formatRow(icon: "photo", primary: format.ext.uppercased(), secondary: nil, size: format.filesize, formatId: format.formatId)
                }
            }

            HStack {
                Spacer()
                Button {
                    Task { await viewModel.download() }
                } label: {
                    if viewModel.starting {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("Download")
                    }
                }
                .disabled(viewModel.starting || viewModel.selectedFormatId == nil)
            }
        }
    }

    private func formatList<Format>(_ formats: [Format], @ViewBuilder row: @escaping (Format) -> some View) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(formats.enumerated()), id: \.offset) { _, format in
                row(format)
                Divider()
            }
        }
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.separator))
    }

    private func formatRow(icon: String, primary: String, secondary: String?, size: Int64?, formatId: String, trailing: String? = nil) -> some View {
        Button {
            viewModel.selectedFormatId = formatId
        } label: {
            HStack {
                Image(systemName: viewModel.selectedFormatId == formatId ? "largecircle.fill.circle" : "circle")
                Image(systemName: icon).foregroundStyle(.secondary)
                Text(primary).frame(width: 70, alignment: .leading)
                if let secondary { Text(secondary).foregroundStyle(.secondary).frame(width: 100, alignment: .leading) }
                if let trailing { Text(trailing).foregroundStyle(.secondary) }
                Spacer()
                Text(formatSize(size)).foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
            .padding(.horizontal, 10).padding(.vertical, 6)
        }
        .buttonStyle(.plain)
    }

    private var batchSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextEditor(text: $viewModel.batchText)
                .frame(minHeight: 120)
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.separator))

            Toggle(isOn: Binding(get: { viewModel.audioOnly }, set: { viewModel.audioOnly = $0 })) {
                Label("Audio only", systemImage: "music.note")
            }
            .toggleStyle(.switch)

            HStack {
                Button {
                    Task { await viewModel.submitBatch() }
                } label: {
                    if viewModel.batchRunning {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("Add all to queue")
                    }
                }
                .disabled(viewModel.batchRunning || viewModel.batchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                if !viewModel.batchRunning, !viewModel.batchItems.isEmpty {
                    Button("Go to Queue") { AppNavigationState.shared.selectedSection = .queue }
                }
            }

            if !viewModel.batchItems.isEmpty {
                VStack(spacing: 0) {
                    ForEach(viewModel.batchItems) { item in
                        HStack {
                            switch item.status {
                            case .pending: Circle().strokeBorder().frame(width: 10, height: 10)
                            case .working: ProgressView().controlSize(.small)
                            case .done: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                            case .error: Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
                            }
                            Text(item.message ?? item.url).lineLimit(1).truncationMode(.tail)
                        }
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        Divider()
                    }
                }
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.separator))
            }
        }
    }
}
