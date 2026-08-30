import AppKit
import SwiftUI

/// Ports `pages/Settings.tsx`. Plain `@AppStorage`, no view model — every key
/// matches what `AppSettings`'s read-only helpers (Home/Watch/download flow)
/// already look up, so a change here takes effect on the very next fetch/
/// download without any extra wiring.
struct SettingsView: View {
    @AppStorage("dkb-downloader:outputDir") private var outputDir = ""
    @AppStorage("dkb-downloader:outputFormat") private var outputFormat = "mp4"
    @AppStorage("dkb-downloader:theme") private var theme = "system"
    @AppStorage("dkb-downloader:notificationsEnabled") private var notificationsEnabled = true
    @AppStorage("dkb-downloader:embedMetadata") private var embedMetadata = false
    @AppStorage("dkb-downloader:cookiesBrowser") private var cookiesBrowser = "none"
    @AppStorage("dkb-downloader:useAria2c") private var useAria2c = false

    var body: some View {
        Form {
            Section("Output") {
                HStack {
                    TextField("Output folder", text: $outputDir).disabled(true)
                    Button("Browse…") { browseOutputDir() }
                }
                Picker("Output format", selection: $outputFormat) {
                    Text("MP4").tag("mp4")
                    Text("MKV").tag("mkv")
                }
            }

            Section("Appearance") {
                Picker("Theme", selection: $theme) {
                    Text("Light").tag("light")
                    Text("Dark").tag("dark")
                    Text("System").tag("system")
                }
                .pickerStyle(.segmented)
            }

            Section("Downloads") {
                Toggle("Embed metadata (thumbnail, chapters, subtitles)", isOn: $embedMetadata)
                Toggle("Use aria2c external downloader", isOn: $useAria2c)
                Picker("Read cookies from browser", selection: $cookiesBrowser) {
                    Text("None").tag("none")
                    Text("Safari").tag("safari")
                    Text("Chrome").tag("chrome")
                    Text("Firefox").tag("firefox")
                    Text("Edge").tag("edge")
                    Text("Brave").tag("brave")
                }
            }

            Section("Notifications") {
                Toggle("Enable notifications", isOn: $notificationsEnabled)
                    .onChange(of: notificationsEnabled) { _, enabled in
                        guard enabled else { return }
                        Task {
                            await NotificationManager.shared.requestAuthorization()
                            await NotificationManager.shared.notify(
                                title: "DKB Downloader", body: "Notifications are enabled", route: nil
                            )
                        }
                    }
                Button("Open Notification Settings…") { NotificationManager.openSystemNotificationSettings() }
            }
        }
        .padding(20)
        .frame(width: 440)
        .onAppear {
            if outputDir.isEmpty { outputDir = AppSettings.ensureOutputDir() }
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
