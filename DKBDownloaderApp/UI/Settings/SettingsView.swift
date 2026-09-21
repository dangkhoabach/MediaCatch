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
    @AppStorage("dkb-downloader:cookiesFile") private var cookiesFile = ""
    @AppStorage("dkb-downloader:useAria2c") private var useAria2c = false
    @AppStorage("dkb-downloader:maxConcurrentDownloads") private var maxConcurrentDownloads = 3
    @AppStorage("dkb-downloader:clipboardSuggestions") private var clipboardSuggestions = true
    @AppStorage("dkb-downloader:rateLimitMBs") private var rateLimitMBs = 0
    @AppStorage("dkb-downloader:subtitleLanguages") private var subtitleLanguages = "en,vi"

    @State private var ytdlpVersion: String?
    @State private var checkingYtdlpUpdate = false
    @State private var ytdlpUpdateMessage: String?
    @State private var automaticUpdateChecks = AppUpdater.automaticallyChecksForUpdates

    var body: some View {
        Form {
            Section(t("settings.section.output")) {
                HStack {
                    TextField(t("settings.outputDir"), text: $outputDir).disabled(true)
                    Button(t("settings.browse")) {
                        if let picked = OutputDirWarningView.pickOutputDir(current: outputDir) { outputDir = picked }
                    }
                }
                OutputDirWarningView()
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
                Toggle(t("settings.clipboardSuggestions"), isOn: $clipboardSuggestions)
                Text(t("settings.clipboardSuggestionsHint")).font(.caption).foregroundStyle(.secondary)
                Picker(t("settings.rateLimit"), selection: $rateLimitMBs) {
                    Text(t("settings.rateLimit.unlimited")).tag(0)
                    ForEach([1, 2, 5, 10], id: \.self) { megabytes in
                        Text("\(megabytes) MB/s").tag(megabytes)
                    }
                }
                Toggle(t("settings.embedMetadata"), isOn: $embedMetadata)
                Text(t("settings.embedMetadataHint")).font(.caption).foregroundStyle(.secondary)
                // Only has an effect with embedding on — that's what pulls
                // subtitles in to begin with.
                TextField(t("settings.subtitleLanguages"), text: $subtitleLanguages)
                    .disabled(!embedMetadata)
                Text(t("settings.subtitleLanguagesHint")).font(.caption).foregroundStyle(.secondary)
                Toggle(t("settings.useAria2c"), isOn: $useAria2c)
                Text(t("settings.useAria2cHint")).font(.caption).foregroundStyle(.secondary)
                // An exported file wins over the browser picker (yt-dlp
                // refuses both at once), so the picker is disabled rather
                // than left looking as though it still applies.
                Picker(t("settings.cookiesBrowser"), selection: $cookiesBrowser) {
                    Text(t("settings.cookiesBrowser.none")).tag("none")
                    Text(t("settings.cookiesBrowser.safari")).tag("safari")
                    Text(t("settings.cookiesBrowser.chrome")).tag("chrome")
                    Text(t("settings.cookiesBrowser.firefox")).tag("firefox")
                    Text(t("settings.cookiesBrowser.edge")).tag("edge")
                    Text(t("settings.cookiesBrowser.brave")).tag("brave")
                }
                .disabled(!cookiesFile.isEmpty)
                Text(t("settings.cookiesBrowserHint")).font(.caption).foregroundStyle(.secondary)

                HStack {
                    Text(t("settings.cookiesFile"))
                    Spacer()
                    Text(cookiesFile.isEmpty ? t("settings.cookiesFile.none") : (cookiesFile as NSString).lastPathComponent)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Button(t("settings.cookiesFile.choose")) { browseCookiesFile() }
                    if !cookiesFile.isEmpty {
                        Button(t("settings.cookiesFile.clear")) { cookiesFile = "" }
                    }
                }
                // A path saved earlier can stop resolving — the file was
                // moved, or it lived in a folder that's since gone. Silently
                // ignoring it (which is what AppSettings does) would look
                // like the setting simply stopped working.
                if !cookiesFile.isEmpty, !FileManager.default.fileExists(atPath: cookiesFile) {
                    Text(t("settings.cookiesFileMissing")).font(.caption).foregroundStyle(.orange)
                } else {
                    Text(t("settings.cookiesFileHint")).font(.caption).foregroundStyle(.secondary)
                }
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

            Section(t("settings.section.updates")) {
                Toggle(t("settings.autoUpdateChecks"), isOn: Binding(
                    get: { automaticUpdateChecks },
                    set: {
                        automaticUpdateChecks = $0
                        AppUpdater.automaticallyChecksForUpdates = $0
                    }
                ))
                Text(t("settings.autoUpdateChecksHint")).font(.caption).foregroundStyle(.secondary)
                HStack {
                    Spacer()
                    Button(t("settings.checkAppUpdateNow")) { AppUpdater.checkForUpdates() }
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
            // Sparkle's first-launch prompt can change this after the view was built.
            automaticUpdateChecks = AppUpdater.automaticallyChecksForUpdates
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

    /// Any file, not just one named cookies.txt — browser extensions export
    /// these under all sorts of names, and the format is what matters.
    private func browseCookiesFile() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        if !cookiesFile.isEmpty {
            panel.directoryURL = URL(fileURLWithPath: cookiesFile).deletingLastPathComponent()
        }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        cookiesFile = url.path
    }
}
