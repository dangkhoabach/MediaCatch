import AppKit
import DKBDownloaderCore
import SwiftUI

/// Ports `pages/Settings.tsx`. Plain `@AppStorage`, no view model — every key
/// matches what `AppSettings`'s read-only helpers (Home/Watch/download flow)
/// already look up, so a change here takes effect on the very next fetch/
/// download without any extra wiring.
///
/// Lives as its own sidebar tab in `ContentView` (not a separate `Settings {}`
/// scene/window) so the app menu's Cmd+, and the menu bar tray's "Settings…"
/// item both land on this exact same view instead of two different surfaces.
struct SettingsView: View {
    @AppStorage("dkb-downloader:outputDir") private var outputDir = ""
    @AppStorage("dkb-downloader:outputFormat") private var outputFormat = "mp4"
    @AppStorage("dkb-downloader:theme") private var theme = "system"
    @AppStorage("dkb-downloader:notificationsEnabled") private var notificationsEnabled = true
    @AppStorage("dkb-downloader:embedMetadata") private var embedMetadata = false
    @AppStorage("dkb-downloader:cookiesBrowser") private var cookiesBrowser = "none"
    @AppStorage("dkb-downloader:useAria2c") private var useAria2c = false
    @AppStorage("dkb-downloader:maxConcurrentDownloads") private var maxConcurrentDownloads = 3

    @State private var ytdlpVersion: String?
    @State private var checkingYtdlpUpdate = false
    @State private var ytdlpUpdateMessage: String?

    var body: some View {
        Form {
            Section(t("settings.section.output")) {
                HStack {
                    TextField(t("settings.outputDir"), text: $outputDir).disabled(true)
                    Button("Browse…") { browseOutputDir() }
                }
                Picker(t("settings.outputFormat"), selection: $outputFormat) {
                    Text("MP4").tag("mp4")
                    Text("MKV").tag("mkv")
                }
            }

            Section(t("settings.section.appearance")) {
                Picker(t("settings.theme"), selection: $theme) {
                    Text(t("settings.theme.light")).tag("light")
                    Text(t("settings.theme.dark")).tag("dark")
                    Text(t("settings.theme.system")).tag("system")
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                Picker(t("settings.language"), selection: Binding(
                    get: { LocalizationCenter.shared.locale },
                    set: { LocalizationCenter.shared.locale = $0 }
                )) {
                    Text("VI").tag(AppLocale.vi)
                    Text("EN").tag(AppLocale.en)
                }
                .pickerStyle(.segmented)
            }

            Section(t("settings.section.downloads")) {
                Picker(t("settings.maxConcurrent"), selection: $maxConcurrentDownloads) {
                    ForEach([1, 2, 3, 5, 10], id: \.self) { count in
                        Text("\(count)").tag(count)
                    }
                }
                // Takes effect on the running manager straight away: raising
                // it admits whatever is already waiting, lowering it only
                // applies to downloads that haven't started yet.
                .onChange(of: maxConcurrentDownloads) { _, value in
                    Task { await AppServices.downloadManager.setMaxConcurrent(value) }
                }
                Text(t("settings.maxConcurrentHint")).font(.caption).foregroundStyle(.secondary)
                Toggle(t("settings.embedMetadata"), isOn: $embedMetadata)
                Text(t("settings.embedMetadataHint")).font(.caption).foregroundStyle(.secondary)
                Toggle(t("settings.useAria2c"), isOn: $useAria2c)
                Text(t("settings.useAria2cHint")).font(.caption).foregroundStyle(.secondary)
                Picker(t("settings.cookiesBrowser"), selection: $cookiesBrowser) {
                    Text(t("settings.cookiesBrowser.none")).tag("none")
                    Text(t("settings.cookiesBrowser.safari")).tag("safari")
                    Text(t("settings.cookiesBrowser.chrome")).tag("chrome")
                    Text(t("settings.cookiesBrowser.firefox")).tag("firefox")
                    Text(t("settings.cookiesBrowser.edge")).tag("edge")
                    Text(t("settings.cookiesBrowser.brave")).tag("brave")
                }
                Text(t("settings.cookiesBrowserHint")).font(.caption).foregroundStyle(.secondary)
            }

            Section(t("settings.section.ytdlp")) {
                HStack {
                    Text(t("settings.ytdlpVersion", ["version": ytdlpVersion ?? "…"]))
                    Spacer()
                    if checkingYtdlpUpdate {
                        ProgressView().controlSize(.small)
                    } else {
                        Button(t("settings.checkYtdlpUpdate")) { Task { await checkYtdlpUpdate() } }
                    }
                }
                if let ytdlpUpdateMessage {
                    Text(ytdlpUpdateMessage).font(.caption).foregroundStyle(.secondary)
                }
            }

            Section(t("settings.notifications")) {
                Toggle(t("settings.notifications"), isOn: $notificationsEnabled)
                    .onChange(of: notificationsEnabled) { _, enabled in
                        guard enabled else { return }
                        Task {
                            await NotificationManager.shared.requestAuthorization()
                            await NotificationManager.shared.notify(
                                title: t("app.name"), body: t("settings.notificationsHint"), route: nil
                            )
                        }
                    }
                Text(t("settings.notificationsHint")).font(.caption).foregroundStyle(.secondary)
                Button(t("settings.openSettings")) { NotificationManager.openSystemNotificationSettings() }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            if outputDir.isEmpty { outputDir = AppSettings.ensureOutputDir() }
        }
        .task { ytdlpVersion = await queryYtdlpVersion() }
    }

    private func queryYtdlpVersion() async -> String {
        guard let runner = try? ProcessRunner(executableURL: AppServices.ytdlpURL, arguments: ["--version"]) else {
            return "?"
        }
        var stdout = ""
        for await event in runner.events {
            if case .stdoutLine(let line) = event { stdout += line }
        }
        return stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func checkYtdlpUpdate() async {
        checkingYtdlpUpdate = true
        defer { checkingYtdlpUpdate = false }
        do {
            if let newVersion = try await AppServices.ytdlpUpdater.updateIfNeeded() {
                ytdlpVersion = newVersion
                ytdlpUpdateMessage = t("settings.ytdlpUpdateDownloaded", ["version": newVersion])
            } else {
                ytdlpUpdateMessage = t("settings.ytdlpUpToDate")
            }
        } catch {
            ytdlpUpdateMessage = t("settings.ytdlpUpdateError")
        }
    }

    private func browseOutputDir() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        if !outputDir.isEmpty { panel.directoryURL = URL(fileURLWithPath: outputDir) }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        outputDir = url.path
    }
}
