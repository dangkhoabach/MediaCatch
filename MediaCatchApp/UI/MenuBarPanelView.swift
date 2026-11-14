import AppKit
import MediaCatchCore
import SwiftUI

/// The menu bar panel, laid out as in the author's other menu bar apps: a
/// header with how many are downloading, the downloads in progress, and a
/// footer with the app-level actions.
///
/// Text goes through `t()` rather than string literals: SwiftUI would
/// localize a literal against the *system* language, ignoring the language
/// picker in Settings that every other surface follows.
struct MenuBarPanelView: View {
    static let width: CGFloat = 360
    /// Past this many, the rest are counted, not listed.
    static let listedLimit = 6

    var body: some View {
        MenuBarPanelContent()
            .frame(width: Self.width)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                StatusBarController.shared.fitPanel(height: height)
            }
            .frame(maxHeight: .infinity, alignment: .top)
    }
}

private struct MenuBarPanelContent: View {
    private let stats = MenuBarStatsViewModel.shared

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(verbatim: "MediaCatch").font(.headline)
                Spacer()
                Text(t("menubar.downloads", ["count": "\(stats.activeDownloadCount)"]))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.top, 10)
            .padding(.bottom, 6)
            Divider()
            downloads
            Divider()
            footer
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private var downloads: some View {
        if stats.activeDownloads.isEmpty {
            Label(t("menubar.noDownloads"), systemImage: "checkmark.circle")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
        } else {
            VStack(spacing: 2) {
                ForEach(stats.activeDownloads.prefix(MenuBarPanelView.listedLimit)) { download in
                    DownloadRow(download: download)
                }
                if stats.activeDownloads.count > MenuBarPanelView.listedLimit {
                    Text(t("menubar.more", ["count": "\(stats.activeDownloads.count - MenuBarPanelView.listedLimit)"]))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 8)
                        .padding(.top, 2)
                }
            }
            .padding(6)
        }
    }

    private var footer: some View {
        HStack(spacing: 2) {
            footerButton(t("menubar.show"), systemImage: "macwindow") { WindowPresenter.showMainWindow() }
            footerButton(t("menubar.settings"), systemImage: "gearshape") { WindowPresenter.showSettings() }
            footerButton(t("menu.checkForUpdates"), systemImage: "arrow.triangle.2.circlepath") { AppUpdater.checkForUpdates() }
            Spacer()
            footerButton(t("menubar.quitApp"), systemImage: "power") { NSApp.terminate(nil) }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }

    private func footerButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 13))
                .frame(width: 28, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .help(title)
        .accessibilityLabel(title)
    }
}

/// One download in progress, or waiting for a slot; opens the queue.
private struct DownloadRow: View {
    let download: Download
    @State private var isHovered = false

    var body: some View {
        Button {
            StatusBarController.shared.closePanel()
            AppNavigationState.shared.selectedSection = .queue
            WindowPresenter.showMainWindow()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: download.status == .downloading ? "arrow.down.circle.fill" : "clock")
                    .foregroundStyle(download.status == .downloading ? Color.accentColor : .secondary)
                VStack(alignment: .leading, spacing: 1) {
                    Text(verbatim: download.title.isEmpty ? download.url : download.title).lineLimit(1)
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
            .background(isHovered ? Color.primary.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }

    /// The live percentage and speed while it downloads; waiting otherwise.
    private var detail: String {
        guard download.status == .downloading else { return t("menubar.waiting") }
        guard let id = download.id, let progress = DownloadEventCenter.shared.progressById[id] else { return t("menubar.starting") }
        return [progress.percent, progress.speed].filter { !$0.isEmpty }.joined(separator: " · ")
    }
}
