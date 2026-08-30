import DKBDownloaderCore
import SwiftUI

struct WatchView: View {
    @State private var viewModel = WatchViewModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                TextField(t("watch.urlPlaceholder"), text: $viewModel.url)
                    .textFieldStyle(.roundedBorder)
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
                .disabled(viewModel.adding || viewModel.url.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage).foregroundStyle(.red).font(.callout)
            }

            if viewModel.channels.isEmpty {
                Text(t("watch.empty")).foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(viewModel.channels) { channel in
                            row(channel)
                        }
                    }
                }
            }
        }
        .padding(20)
        .task { viewModel.refresh() }
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
            Button { viewModel.remove(channel.id ?? -1) } label: { Image(systemName: "trash") }.buttonStyle(.plain)
        }
        .padding(10)
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.separator))
    }
}
