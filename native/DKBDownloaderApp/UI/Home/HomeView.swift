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
        // A plain, unstyled `Button` — not a `Toggle`, even a `.button`-styled
        // one — matching DKB Monitor's proven lesson: anything but a bare
        // `Button` here stops looking like a "real" toolbar control to the
        // system and falls back to a generic floating switch instead of the
        // native round toolbar-button chrome (and its Liquid Glass material
        // on macOS 26+). The icon itself reflects on/off state.
        .toolbar {
            ToolbarItemGroup(placement: .automatic) {
                Button {
                    viewModel.batchMode.toggle()
                    viewModel.batchItems = []
                } label: {
                    Label(t("home.batchMode"), systemImage: viewModel.batchMode ? "list.bullet.rectangle.fill" : "list.bullet.rectangle")
                }
            }
        }
        .task(id: AppNavigationState.shared.pendingFetchUrl) {
            if let pending = AppNavigationState.shared.pendingFetchUrl {
                await viewModel.handlePendingFetch(pending)
            }
        }
    }

    private var fetchSection: some View {
        HStack {
            TextField(t("home.urlPlaceholder"), text: $viewModel.url)
                .textFieldStyle(.roundedBorder)
                .controlSize(.large)
                .onSubmit { Task { await viewModel.fetchInfo() } }
            // `.borderedProminent` + `.defaultAction` — the standard macOS
            // treatment for a screen's one primary action (same tint/weight
            // as a dialog's default "OK" button), so it doesn't read as a
            // plain, secondary control next to the text field.
            Button {
                Task { await viewModel.fetchInfo() }
            } label: {
                if viewModel.loading {
                    ProgressView().controlSize(.small)
                } else {
                    Text(t("home.fetchInfo"))
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
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
            // `GroupBox` (not a hand-drawn container) so this picks up the
            // system's automatic card material — Liquid Glass on macOS 26+
            // — with no styling of our own, same pattern as DKB Monitor's
            // stat cards.
            GroupBox {
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
                                    .background(.secondary.opacity(0.15), in: Capsule())
                            }
                        }
                        Text(formatDuration(info.duration)).font(.caption).foregroundStyle(.secondary)
                        Spacer(minLength: 0)
                    }
                    Spacer(minLength: 0)
                }
                .padding(6)
            }

            if !videoFormats.isEmpty {
                Toggle(isOn: Binding(get: { viewModel.audioOnly }, set: { viewModel.setAudioOnly($0) })) {
                    Label(t("home.audioOnly"), systemImage: "music.note")
                }
                .toggleStyle(.switch)
            }

            if viewModel.audioOnly, !audioFormats.isEmpty {
                formatList(audioFormats) { format in
                    formatRowLabel(icon: "music.note", primary: format.tbr.map { "\(Int($0))kbps" } ?? "—", secondary: format.ext.uppercased(), size: format.filesize)
                }
            }

            if !viewModel.audioOnly, !videoFormats.isEmpty {
                formatList(videoFormats) { format in
                    formatRowLabel(
                        icon: "video",
                        primary: format.height.map { "\($0)p" } ?? "—",
                        secondary: format.vcodec,
                        size: format.filesize,
                        trailing: format.hasAudio ? t("home.hasAudio") : t("home.noAudio")
                    )
                }
            }

            if videoFormats.isEmpty, !imageFormats.isEmpty {
                formatList(imageFormats) { format in
                    formatRowLabel(icon: "photo", primary: format.ext.uppercased(), secondary: nil, size: format.filesize)
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
                        Text(t("home.download"))
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(viewModel.starting || viewModel.selectedFormatId == nil)
            }
        }
    }

    /// A real `Picker` in `.inline` style (not hand-rolled selectable
    /// `Button` rows) — renders as a native list with a system checkmark
    /// next to the selected row, same idiom System Settings uses for
    /// "pick one of these" lists, and gets the right materials for free.
    private func formatList(_ formats: [VideoFormat], @ViewBuilder row: @escaping (VideoFormat) -> some View) -> some View {
        Picker("", selection: Binding(
            get: { viewModel.selectedFormatId },
            set: { viewModel.selectedFormatId = $0 }
        )) {
            ForEach(formats, id: \.formatId) { format in
                row(format).tag(Optional(format.formatId))
            }
        }
        .pickerStyle(.inline)
        .labelsHidden()
    }

    private func formatRowLabel(icon: String, primary: String, secondary: String?, size: Int64?, trailing: String? = nil) -> some View {
        HStack {
            Image(systemName: icon).foregroundStyle(.secondary)
            Text(primary).frame(width: 70, alignment: .leading)
            if let secondary { Text(secondary).foregroundStyle(.secondary).frame(width: 100, alignment: .leading) }
            if let trailing { Text(trailing).foregroundStyle(.secondary) }
            Spacer()
            Text(formatSize(size)).foregroundStyle(.secondary)
        }
    }

    private var batchSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            ZStack(alignment: .topLeading) {
                TextEditor(text: $viewModel.batchText)
                if viewModel.batchText.isEmpty {
                    Text(t("home.batchPlaceholder"))
                        .foregroundStyle(.secondary)
                        .padding(.top, 8).padding(.leading, 5)
                        .allowsHitTesting(false)
                }
            }
            .frame(minHeight: 120)
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.separator))

            Toggle(isOn: Binding(get: { viewModel.audioOnly }, set: { viewModel.audioOnly = $0 })) {
                Label(t("home.audioOnly"), systemImage: "music.note")
            }
            .toggleStyle(.switch)

            HStack {
                Button {
                    Task { await viewModel.submitBatch() }
                } label: {
                    if viewModel.batchRunning {
                        ProgressView().controlSize(.small)
                    } else {
                        Text(t("home.batchSubmit"))
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(viewModel.batchRunning || viewModel.batchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                if !viewModel.batchRunning, !viewModel.batchItems.isEmpty {
                    Button(t("nav.queue")) { AppNavigationState.shared.selectedSection = .queue }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                }
            }

            if !viewModel.batchItems.isEmpty {
                // A real `List`, height-capped since it's embedded inside
                // this screen's own `ScrollView` rather than filling the
                // window — same native row chrome as the other screens'
                // lists without fighting the outer scroll view for the
                // gesture.
                List(viewModel.batchItems) { item in
                    HStack {
                        switch item.status {
                        case .pending: Circle().strokeBorder().frame(width: 10, height: 10)
                        case .working: ProgressView().controlSize(.small)
                        case .done: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                        case .error: Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
                        }
                        Text(item.message ?? item.url).lineLimit(1).truncationMode(.tail)
                    }
                }
                .listStyle(.inset)
                .frame(height: min(CGFloat(viewModel.batchItems.count) * 28 + 16, 280))
            }
        }
    }
}
