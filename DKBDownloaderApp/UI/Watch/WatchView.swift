import DKBDownloaderCore
import SwiftUI

struct WatchView: View {
    @State private var viewModel = WatchViewModel()
    @State private var pendingRemoveChannel: WatchedChannel?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                TextField(t("watch.urlPlaceholder"), text: $viewModel.url)
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.large)
                    .onSubmit { Task { await viewModel.add() } }
                Button {
                    Task { await viewModel.add() }
                } label: {
                    if viewModel.adding {
                        ProgressView().controlSize(.small)
                    } else {
                        Text(t("watch.add"))
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(viewModel.adding || viewModel.url.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding()

            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage).foregroundStyle(.red).font(.callout).padding(.horizontal)
            }

            if viewModel.channels.isEmpty {
                Text(t("watch.empty")).foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(viewModel.channels) { channel in
                    row(channel)
                }
                .listStyle(.inset)
            }
        }
        .task { viewModel.refresh() }
        .confirmationDialog(
            t("watch.removeConfirmTitle"),
            isPresented: Binding(
                get: { pendingRemoveChannel != nil },
                set: { if !$0 { pendingRemoveChannel = nil } }
            )
        ) {
            Button(t("watch.remove"), role: .destructive) {
                if let channel = pendingRemoveChannel {
                    viewModel.remove(channel.id ?? -1)
                }
                pendingRemoveChannel = nil
            }
        }
    }

    private func row(_ channel: WatchedChannel) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(channel.title).font(.callout).lineLimit(1)
                Text(
                    channel.lastCheckedAt.map { t("watch.lastChecked", ["time": $0.formatted(date: .abbreviated, time: .shortened)]) }
                        ?? t("watch.neverChecked")
                )
                .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("", isOn: Binding(
                get: { channel.enabled },
                set: { viewModel.toggle(channel.id ?? -1, enabled: $0) }
            ))
            .toggleStyle(.switch)
            .labelsHidden()
            .accessibilityLabel(t("watch.enabledToggle"))
            Button { pendingRemoveChannel = channel } label: { Image(systemName: "trash") }
                .buttonStyle(.plain)
                .accessibilityLabel(t("watch.remove"))
        }
        .padding(.vertical, 6)
    }
}
