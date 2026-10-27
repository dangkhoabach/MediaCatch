import AppKit
import SwiftUI

/// Tells the user the download folder can't be written to, and gives them
/// the two ways out: re-allow the app in System Settings (the only fix for
/// a TCC "Don't Allow"), or pick a different folder. Shown on Home so it's
/// seen before a download starts, and in Settings next to the folder itself.
///
/// The probe runs off the main thread because macOS blocks inside the
/// filesystem call while its folder-access prompt is up. It re-runs every
/// time the app becomes active, so the banner clears on its own once the
/// user has flipped the switch in System Settings and come back.
struct OutputDirWarningView: View {
    @AppStorage("dkb-downloader:outputDir") private var outputDir = ""
    @State private var problem: AppSettings.OutputDirProblem?

    var body: some View {
        Group {
            if let problem {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                        Text(message(for: problem))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .font(.caption)
                    HStack {
                        if problem == .accessDenied {
                            Button(t("outputDir.openSystemSettings")) { Self.openFilesAndFoldersSettings() }
                        }
                        Button(t("outputDir.chooseFolder")) {
                            if let picked = Self.pickOutputDir(current: outputDir) { outputDir = picked }
                        }
                    }
                    .controlSize(.small)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
            }
        }
        .task(id: outputDir) { await recheck() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await recheck() }
        }
    }

    private func message(for problem: AppSettings.OutputDirProblem) -> String {
        let folder = (outputDir as NSString).abbreviatingWithTildeInPath
        switch problem {
        case .accessDenied:
            return t("outputDir.accessDenied", ["folder": folder])
        case .volumeMissing:
            return t("outputDir.volumeMissing", ["folder": folder])
        case .unreachable(let reason):
            return t("outputDir.unreachable", ["folder": folder, "reason": reason])
        }
    }

    private func recheck() async {
        let path = outputDir.isEmpty ? AppSettings.ensureOutputDir() : outputDir
        let result = await Task.detached { AppSettings.outputDirProblem(path) }.value
        problem = result
    }

    /// Lands on Privacy & Security › Files and Folders, where the app shows
    /// up with its Downloads/Desktop/Documents switches once it has asked.
    static func openFilesAndFoldersSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_FilesAndFolders")!
        NSWorkspace.shared.open(url)
    }

    /// Shared with Settings' Browse button so both surfaces pick the same
    /// way. A folder chosen through the panel is also one macOS lets the app
    /// use — the choice itself counts as permission.
    static func pickOutputDir(current: String) -> String? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        if !current.isEmpty { panel.directoryURL = URL(fileURLWithPath: current) }
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        return url.path
    }
}
