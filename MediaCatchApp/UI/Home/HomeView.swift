import AppKit
import MediaCatchCore
import SwiftUI
import UniformTypeIdentifiers

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
    @Bindable private var navigation = AppNavigationState.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let errorMessage = viewModel.errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                        .font(.callout)
                }

                // Before the URL field on purpose: a folder macOS won't let
                // the app write to fails every download at the very end.
                OutputDirWarningView()

                if viewModel.batchMode {
                    batchSection
                } else {
                    fetchSection
                    warningsSection
                    if let info = viewModel.info {
                        infoSection(info)
                    }
                }
            }
            .padding(24)
        }
        .frame(minWidth: 480, minHeight: 360)
        // A plain, unstyled `Button` — not a `Toggle`, even a `.button`-styled
        // one — matching SignalBar's proven lesson: anything but a bare
        // `Button` here stops looking like a "real" toolbar control to the
        // system and falls back to a generic floating switch instead of the
        // native round toolbar-button chrome (and its Liquid Glass material
        // on macOS 26+). The icon itself reflects on/off state.
        // Guarded the same way as LibraryView's toolbar: `.toolbar` content
        // is collected regardless of this view's own opacity, and with all
        // four tabs staying mounted at once it would otherwise keep showing
        // up while another tab is active.
        .toolbar {
            if navigation.selectedSection == .home {
                ToolbarItemGroup(placement: .automatic) {
                    Button {
                        viewModel.batchMode.toggle()
                        viewModel.batchItems = []
                    } label: {
                        Label(t("home.batchMode"), systemImage: viewModel.batchMode ? "list.bullet.rectangle.fill" : "list.bullet.rectangle")
                    }
                }
            }
        }
        .task(id: AppNavigationState.shared.pendingFetchUrl) {
            if let pending = AppNavigationState.shared.pendingFetchUrl {
                viewModel.handlePendingFetch(pending)
            }
        }
        // Mirrors the old Tauri app's page-level `onDrop`: dragging a link
        // in (e.g. from Safari's address bar) fills the URL field and kicks
        // off Fetch Info in one action, instead of requiring copy-paste.
        // Tries `.url` first (what a browser address-bar drag provides),
        // falling back to plain text — matching the old `text/uri-list` then
        // `text/plain` fallback.
        .onDrop(of: [.url, .plainText], isTargeted: nil, perform: handleDrop)
        // "Copy a link in the browser, switch back here" is the common path,
        // so offer it on activation — and on first appearance, since the app
        // may already be frontmost when Home is first shown.
        .onAppear { viewModel.suggestClipboardURL() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            guard navigation.selectedSection == .home else { return }
            viewModel.suggestClipboardURL()
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        if provider.canLoadObject(ofClass: URL.self) {
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                Task { @MainActor in
                    viewModel.url = url.absoluteString
                    viewModel.startFetch()
                }
            }
            return true
        }
        if provider.canLoadObject(ofClass: NSString.self) {
            _ = provider.loadObject(ofClass: NSString.self) { text, _ in
                guard let text = text as? String, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                Task { @MainActor in
                    viewModel.url = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    viewModel.startFetch()
                }
            }
            return true
        }
        return false
    }

    /// yt-dlp's own warnings from the last successful fetch. Deliberately
    /// understated — orange, not red, and never blocking — because the fetch
    /// did work; this is "here's why the result might be worse than you
    /// expect", not a failure. Selectable since the warnings tend to carry a
    /// URL explaining what to install.
    @ViewBuilder
    private var warningsSection: some View {
        if !viewModel.fetchWarnings.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text(t("home.ytdlpWarning"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.orange)
                ForEach(viewModel.fetchWarnings, id: \.self) { warning in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text(warning)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private var fetchSection: some View {
        HStack {
            TextField(t("home.urlPlaceholder"), text: $viewModel.url)
                .textFieldStyle(.roundedBorder)
                .controlSize(.large)
                .onSubmit { viewModel.startFetch() }
            fetchInfoButton
        }
    }

    /// Only one `.borderedProminent` action on screen at a time, per Apple
    /// HIG: once info's loaded, Download (below) is the screen's primary
    /// action, so this steps back to `.bordered` instead of the two of them
    /// competing as equally "primary" blue buttons. `.buttonStyle` takes a
    /// concrete style type, so the two cases need separate `Button`s rather
    /// than one ternary on the modifier.
    @ViewBuilder
    private var fetchInfoButton: some View {
        if viewModel.loading {
            // Spinner *and* a way out: a stalled extraction otherwise left
            // this spinning with nothing to press until the 90s timeout.
            // Cancel kills the yt-dlp process, not just the Swift task.
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Button(t("home.fetchCancel")) { viewModel.cancelFetch() }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
            }
        } else {
            let isDisabled = viewModel.url.trimmingCharacters(in: .whitespaces).isEmpty
            if viewModel.info == nil {
                Button(t("home.fetchInfo")) { viewModel.startFetch() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(isDisabled)
            } else {
                Button(t("home.fetchInfo")) { viewModel.startFetch() }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .disabled(isDisabled)
            }
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

                    // Only offered when the video actually has chapters —
                    // yt-dlp would simply produce nothing extra otherwise,
                    // which reads as the toggle being broken.
                    if info.chapterCount > 0 {
                        Toggle(isOn: $viewModel.splitChapters) {
                            Label(
                                t("home.splitChapters", ["count": String(info.chapterCount)]),
                                systemImage: "scissors"
                            )
                        }
                        .toggleStyle(.switch)
                    }
                }
            }
            .padding(12)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))

            if viewModel.audioOnly, !audioFormats.isEmpty {
                formatTable(audioFormats, icon: "music.note")
            }

            if !viewModel.audioOnly, !videoFormats.isEmpty {
                if videoFormats.contains(where: { !$0.hasAudio }) {
                    Text(t("home.noAudioHint"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
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

    /// Hand-built rows, not a SwiftUI `Table` — a real `Table` always draws
    /// its own header row, and the reference screenshot from the old Tauri
    /// app has no header at all: just a radio dot, icon, and columns lined
    /// up with fixed-width frames, thin dividers between rows, and a single
    /// rounded card around the whole thing. That look isn't reachable with
    /// `Table`'s public API, so this reproduces it directly.
    private func formatTable(_ formats: [VideoFormat], icon: String) -> some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(Array(formats.enumerated()), id: \.element.id) { index, format in
                    formatRow(format, icon: icon, isEven: index.isMultiple(of: 2))
                    if index < formats.count - 1 {
                        Divider().opacity(0.5)
                    }
                }
            }
        }
        .frame(height: min(CGFloat(formats.count) * 44 + 2, 320))
        .background(Color.black.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.separator))
    }

    private func formatRow(_ format: VideoFormat, icon: String, isEven: Bool) -> some View {
        Button {
            viewModel.selectedFormatId = format.id
        } label: {
            HStack(spacing: 14) {
                radioIndicator(selected: format.id == viewModel.selectedFormatId)
                Image(systemName: icon).foregroundStyle(.secondary).frame(width: 16)
                Text(qualityLabel(format))
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 64, alignment: .leading)
                Text(format.fps.map { "\(Int($0))fps" } ?? "—")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(width: 56, alignment: .leading)
                Text(codecLabel(format))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 90, alignment: .leading)
                Text(format.hasAudio ? t("home.hasAudio") : t("home.noAudio"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(width: 90, alignment: .leading)
                Spacer(minLength: 0)
                Text(formatSize(format.filesize))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 13)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(isEven ? Color.clear : Color.white.opacity(0.03))
    }

    private func radioIndicator(selected: Bool) -> some View {
        ZStack {
            Circle()
                .strokeBorder(selected ? Color.accentColor : Color.secondary.opacity(0.6), lineWidth: 1.5)
                .frame(width: 14, height: 14)
            if selected {
                Circle().fill(Color.accentColor).frame(width: 7, height: 7)
            }
        }
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
                // A bare `TextEditor` has no top inset of its own — the
                // caret (and first line typed) sits flush against the box's
                // top edge with no breathing room. `.padding(.top, 8)` here
                // gives it the same clearance the placeholder below already
                // has, instead of only inset-ing the placeholder.
                TextEditor(text: $viewModel.batchText)
                    .padding(.top, 8)
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
