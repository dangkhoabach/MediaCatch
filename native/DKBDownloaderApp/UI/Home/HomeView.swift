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

        VStack(alignment: .leading, spacing: 20) {
            // An explicit `.regularMaterial` fill (still a system material,
            // not a hand-painted color — Liquid Glass on macOS 26+ applies
            // to it the same as any other system surface) instead of a bare
            // `GroupBox`: GroupBox's own automatic border reads as
            // essentially invisible against this app's dark background,
            // leaving the thumbnail/title looking like it's floating with
            // no card at all. The audio-only toggle now lives in the same
            // card (below a `Divider`) instead of sitting alone in its own
            // unbounded row.
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
                                    .background(.secondary.opacity(0.15), in: Capsule())
                            }
                        }
                        Text(formatDuration(info.duration)).font(.caption).foregroundStyle(.secondary)
                        Spacer(minLength: 0)
                    }
                    Spacer(minLength: 0)
                }

                if !videoFormats.isEmpty {
                    Divider()
                    Toggle(isOn: Binding(get: { viewModel.audioOnly }, set: { viewModel.setAudioOnly($0) })) {
                        Label(t("home.audioOnly"), systemImage: "music.note")
                    }
                    .toggleStyle(.switch)
                }
            }
            .padding(12)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))

            if viewModel.audioOnly, !audioFormats.isEmpty {
                formatTable(audioFormats, icon: "music.note")
            }

            if !viewModel.audioOnly, !videoFormats.isEmpty {
                formatTable(videoFormats, icon: "video")
            }

            if videoFormats.isEmpty, !imageFormats.isEmpty {
                formatTable(imageFormats, icon: "photo")
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

    /// A real `Table` — genuine NSTableView-backed columns with headers,
    /// not a hand-spaced `HStack` — selecting a row highlights the whole
    /// row the same way Finder's list view does, which is what actually
    /// communicates "this one's picked" in a table, no extra checkmark/
    /// radio glyph needed.
    private func formatTable(_ formats: [VideoFormat], icon: String) -> some View {
        Table(formats, selection: Binding(
            get: { viewModel.selectedFormatId },
            set: { if let newValue = $0 { viewModel.selectedFormatId = newValue } }
        )) {
            TableColumn(t("home.format.quality")) { format in
                Label(qualityLabel(format), systemImage: icon)
            }
            TableColumn(t("home.format.codec")) { format in
                Text(codecLabel(format)).foregroundStyle(.secondary)
            }
            TableColumn(t("home.format.audio")) { format in
                Text(format.hasAudio ? t("home.hasAudio") : t("home.noAudio")).foregroundStyle(.secondary)
            }
            TableColumn(t("home.format.size")) { format in
                Text(formatSize(format.filesize)).foregroundStyle(.secondary)
            }
        }
        // Zebra striping so adjacent rows are distinguishable at a glance
        // (the default inset style renders every unselected row the same
        // shade), plus a rounded frame so the table reads as its own
        // bounded panel instead of bleeding into the page around it.
        .tableStyle(.inset(alternatesRowBackgrounds: true))
        .frame(height: min(CGFloat(formats.count) * 28 + 30, 280))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.separator))
    }

    private func qualityLabel(_ format: VideoFormat) -> String {
        if let height = format.height { return "\(height)p" }
        if let tbr = format.tbr { return "\(Int(tbr))kbps" }
        return format.ext.uppercased()
    }

    private func codecLabel(_ format: VideoFormat) -> String {
        if format.hasVideo { return format.vcodec }
        if format.hasAudio { return format.acodec }
        return format.ext.uppercased()
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
