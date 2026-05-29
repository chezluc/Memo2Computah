import AppKit
import SwiftUI

struct CompanionMenuView: View {
    @ObservedObject var viewModel: CompanionViewModel
    var openSettings: (() -> Void)?
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            statusPanel

            HStack(spacing: 10) {
                Button("Start") {
                    Task { await viewModel.startAgent() }
                }
                .disabled(viewModel.isRunning || viewModel.isBusy)

                Button("Stop") {
                    Task { await viewModel.stopAgent() }
                }
                .disabled(!viewModel.isRunning || viewModel.isBusy)

                Button("Refresh") {
                    Task { await viewModel.refresh() }
                }
                .disabled(viewModel.isBusy)
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label(viewModel.isReceiverRunning ? "Receiver Ready" : "Receiver Offline", systemImage: viewModel.isReceiverRunning ? "antenna.radiowaves.left.and.right" : "antenna.radiowaves.left.and.right.slash")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(viewModel.isReceiverRunning ? .green : .secondary)

                    Spacer()
                }

                Text(viewModel.receiverLANURLString)
                    .font(.caption.monospaced())
                    .textSelection(.enabled)

                Text(viewModel.receiverMessage)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                HStack(spacing: 8) {
                    Button("Start Receiver") {
                        Task { await viewModel.startReceiver() }
                    }
                    .disabled(viewModel.isReceiverRunning)

                    Button("Stop") {
                        viewModel.stopReceiver()
                    }

                    Button("Check") {
                        Task { await viewModel.refreshReceiverStatus() }
                    }
                }
            }
            .padding(10)
            .background(Color.secondary.opacity(0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            HStack(spacing: 10) {
                Button("Skip") {
                    Task { await viewModel.skipCurrentTranscription() }
                }
                .disabled(!viewModel.isTranscribing || viewModel.isBusy)

                Picker("Model", selection: Binding(
                    get: { viewModel.whisperModel },
                    set: { viewModel.setWhisperModel($0) }
                )) {
                    Text("Tiny").tag("tiny")
                    Text("Base").tag("base")
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            if !viewModel.transcriptionSettingsMessage.isEmpty {
                Text(viewModel.transcriptionSettingsMessage)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Divider()

            Button {
                NSApplication.shared.activate(ignoringOtherApps: true)
                if let openSettings {
                    openSettings()
                } else {
                    openWindow(id: "settings")
                }
            } label: {
                Label("Routes and Setup...", systemImage: "slider.horizontal.3")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Divider()

            HStack(spacing: 10) {
                Button("Folder") {
                    viewModel.openWatchFolder()
                }

                Button("Logs") {
                    viewModel.openLogsFolder()
                }

                Spacer()

                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
            }
        }
        .padding(16)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: "waveform.circle.fill")
                .font(.system(size: 34))
                .foregroundStyle(viewModel.isRunning ? .green : .secondary)

            VStack(alignment: .leading, spacing: 3) {
                Text("Memo2Computah")
                    .font(.title3.weight(.semibold))

                Text(viewModel.isRunning ? "Watching \(viewModel.status.watchFolder)" : "Watcher stopped")
                    .foregroundStyle(.secondary)
                    .font(.caption)
                    .lineLimit(1)
            }
        }
    }

    private var statusPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            if viewModel.isProcessing {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(viewModel.progressLabel)
                            .font(.caption.weight(.semibold))

                        Spacer()

                        Text("\(Int(viewModel.progressValue * 100))%")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }

                    ProgressView(value: viewModel.progressValue)
                        .progressViewStyle(.linear)
                }
                .padding(.bottom, 4)
            }

            statusRow("Status", viewModel.status.status.capitalized)
            statusRow("Message", viewModel.status.message)
            statusRow("Model", viewModel.effectiveWhisperModel)
            statusRow("Queue", String(viewModel.status.queueCount))
            statusRow("Processed", String(viewModel.status.filesProcessed))

            if !viewModel.status.currentFile.isEmpty {
                statusRow("Current", viewModel.status.currentFile)
            }

            if !viewModel.status.lastRoute.isEmpty {
                statusRow("Route", viewModel.status.lastRoute)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func statusRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(width: 72, alignment: .leading)

            Text(value.isEmpty ? "-" : value)
                .lineLimit(2)
                .textSelection(.enabled)
        }
        .font(.caption)
    }
}
