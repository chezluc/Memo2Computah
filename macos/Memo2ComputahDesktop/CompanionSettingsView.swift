import AppKit
import SwiftUI

struct CompanionSettingsView: View {
    @ObservedObject var viewModel: CompanionViewModel

    var body: some View {
        NavigationSplitView {
            List {
                NavigationLink {
                    setupView
                } label: {
                    Label("Setup", systemImage: "checklist")
                }

                NavigationLink {
                    routesView
                } label: {
                    Label("Routes", systemImage: "arrow.triangle.branch")
                }

                NavigationLink {
                    releaseReadinessView
                } label: {
                    Label("Release", systemImage: "shippingbox")
                }
            }
            .navigationTitle("Memo2Computah")
        } detail: {
            setupView
        }
    }

    private var setupView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                sectionHeader(
                    "Setup",
                    subtitle: "The Mac companion receives or watches incoming memos, starts the watcher, and routes finished transcripts."
                )

                setupWizard

                folderSetup

                receiverSetup

                watcherSummary

                HStack(spacing: 10) {
                    Button("Start Watcher") {
                        Task { await viewModel.startAgent() }
                    }
                    .disabled(viewModel.isRunning || viewModel.isBusy)

                    Button("Stop Watcher") {
                        Task { await viewModel.stopAgent() }
                    }
                    .disabled(!viewModel.isRunning || viewModel.isBusy)

                    Button("Refresh") {
                        Task { await viewModel.refresh() }
                    }
                    .disabled(viewModel.isBusy)

                    Spacer()
                }

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Text("Folders")
                        .font(.headline)

                    HStack(spacing: 10) {
                        Button("Open Drop Folder") {
                            viewModel.openWatchFolder()
                        }

                        Button("Open Logs") {
                            viewModel.openLogsFolder()
                        }

                        Button("Reveal Routes File") {
                            viewModel.revealRoutesFile()
                        }
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle("Setup")
    }

    private var setupWizard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center) {
                Label("First-Run Check", systemImage: "wand.and.sparkles")
                    .font(.headline)

                Spacer()

                Button {
                    Task { await viewModel.runTextEditSetupTest() }
                } label: {
                    if viewModel.isRunningSetupTest {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Text("Run TextEdit Test")
                    }
                }
                .disabled(viewModel.isRunningSetupTest || viewModel.isBusy)
            }

            VStack(alignment: .leading, spacing: 9) {
                setupWizardRow(
                    "1",
                    "Confirm the watcher is listening",
                    viewModel.isRunning ? "Watching the Dropbox drop folder." : "Not listening yet. The test can start it."
                )
                setupWizardRow(
                    "2",
                    "Send a known test job",
                    "The companion drops a tiny text job into the same folder the iPhone uses."
                )
                setupWizardRow(
                    "3",
                    "Verify routing in TextEdit",
                    "TextEdit should open and receive the setup sentence. That proves the watcher, clipboard, and AppleScript route are connected."
                )
            }

            if !viewModel.setupTestMessage.isEmpty {
                Text(viewModel.setupTestMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
        .padding(14)
        .background(Color.accentColor.opacity(0.10), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.accentColor.opacity(0.18), lineWidth: 1)
        )
    }

    private var folderSetup: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Shared Script Folder")
                .font(.headline)

            Text("Memo2Computah uses shared scripts from this repo, but all Memo2 Dropbox and LAN jobs land in ~/Dropbox/Memo2Computah.")
                .font(.caption)
                .foregroundStyle(.secondary)

            TextField("Shared script folder", text: $viewModel.basePathString)
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
                .disabled(viewModel.isRunning)

            HStack(spacing: 10) {
                Button("Choose Folder") {
                    viewModel.chooseBaseFolder()
                }
                .disabled(viewModel.isRunning)

                Button("Reset") {
                    viewModel.resetBaseFolder()
                }
                .disabled(viewModel.isRunning)

                if viewModel.isRunning {
                    Text("Stop the watcher before changing folders.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(14)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var receiverSetup: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(viewModel.isReceiverRunning ? "Local Receiver Ready" : "Local Receiver Offline", systemImage: viewModel.isReceiverRunning ? "antenna.radiowaves.left.and.right" : "antenna.radiowaves.left.and.right.slash")
                    .font(.headline)
                    .foregroundStyle(viewModel.isReceiverRunning ? .green : .secondary)

                Spacer()

                Button("Check") {
                    Task { await viewModel.refreshReceiverStatus() }
                }
            }

            Text("This starts the local HTTP receiver used by Memo2Computah for LAN uploads. The iPhone should use the LAN URL while both devices are on the same network.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 8) {
                GridRow {
                    Text("Port")
                        .foregroundStyle(.secondary)
                    TextField("8943", text: $viewModel.receiverPortString)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 96)
                }

                GridRow {
                    Text("LAN URL")
                        .foregroundStyle(.secondary)
                    Text(viewModel.receiverLANURLString)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                }

                GridRow {
                    Text("Local URL")
                        .foregroundStyle(.secondary)
                    Text(viewModel.receiverLocalURLString)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                }

                GridRow {
                    Text("API Token")
                        .foregroundStyle(.secondary)
                    HStack(spacing: 8) {
                        SecureField("Receiver API token", text: $viewModel.receiverAPIToken)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 360)

                        Button("Copy") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(viewModel.receiverAPIToken, forType: .string)
                        }

                        Button("Generate") {
                            viewModel.generateReceiverAPIToken()
                        }
                    }
                }
            }

            Text("Copy this token into Memo2 on iPhone. After changing it, restart the receiver so LAN and Cloudflare uploads require the new token.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(viewModel.receiverMessage)
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)

            HStack(spacing: 10) {
                Button("Start Receiver") {
                    Task { await viewModel.startReceiver() }
                }
                .disabled(viewModel.isReceiverRunning)

                Button("Stop Receiver") {
                    viewModel.stopReceiver()
                }

                Button("Open Local Receiver") {
                    viewModel.openReceiverURL()
                }

                Spacer()
            }
        }
        .padding(14)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var routesView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top) {
                sectionHeader(
                    "Routes",
                    subtitle: "Edit the desktop route contract used by the watcher. Routes map spoken commands and selected iPhone destinations to Mac apps or tmux targets."
                )

                    Spacer()

                    Button {
                        viewModel.addRoute()
                    } label: {
                        Label("Add Route", systemImage: "plus")
                    }
                }

                if !viewModel.routeMessage.isEmpty {
                    Text(viewModel.routeMessage)
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }

                VStack(spacing: 12) {
                    ForEach($viewModel.routeDrafts) { $route in
                        routeCard(route: $route)
                    }
                }

                HStack(spacing: 10) {
                    Button("Save Routes") {
                        viewModel.saveRoutes()
                    }
                    .buttonStyle(.borderedProminent)

                    Button("Reload") {
                        viewModel.loadRoutes()
                    }

                    Button("Defaults") {
                        viewModel.restoreDefaultRoutes()
                    }

                    Spacer()
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle("Routes")
    }

    private var releaseReadinessView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                sectionHeader(
                    "Release Readiness",
                    subtitle: "Current packaging notes for getting the iPhone recorder and Mac companion ready for TestFlight."
                )

                readinessRow("Bundle IDs", "Use stable explicit bundle IDs for the iOS app, widget/control extension, and macOS companion.")
                readinessRow("Signing", "Use the active Apple Developer team and automatic signing for development. Use App Store distribution profiles for TestFlight uploads.")
                readinessRow("Sandboxing", "The Mac companion currently launches scripts and watches Dropbox. Before App Store distribution, review sandbox, file access, automation, and Apple Events permissions.")
                readinessRow("Onboarding", "The iPhone app should explain Dropbox OAuth, default folder selection, and the required Mac companion.")
                readinessRow("Privacy", "Add clear microphone, speech recognition, Dropbox, and local automation explanations in app copy and App Store privacy answers.")
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle("Release")
    }

    private var watcherSummary: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(viewModel.isRunning ? "Watching" : "Stopped", systemImage: viewModel.isRunning ? "eye.fill" : "eye.slash")
                    .font(.headline)
                    .foregroundStyle(viewModel.isRunning ? .green : .secondary)

                Spacer()

                if viewModel.isProcessing {
                    Text("\(Int(viewModel.progressValue * 100))%")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }

            if viewModel.isProcessing {
                ProgressView(value: viewModel.progressValue)
                    .progressViewStyle(.linear)
            }

            settingsStatusRow("Status", viewModel.status.status.capitalized)
            settingsStatusRow("Message", viewModel.status.message)
            settingsStatusRow("Queue", String(viewModel.status.queueCount))
            settingsStatusRow("Processed", String(viewModel.status.filesProcessed))
            settingsStatusRow("Drop Folder", viewModel.status.watchFolder)

            if !viewModel.status.currentFile.isEmpty {
                settingsStatusRow("Current", viewModel.status.currentFile)
            }

            if !viewModel.status.lastRoute.isEmpty {
                settingsStatusRow("Last Route", viewModel.status.lastRoute)
            }
        }
        .padding(14)
        .background(Color.secondary.opacity(0.10), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func routeCard(route: Binding<RouteDefinition>) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                TextField("Label", text: route.label)
                    .font(.system(size: 14, weight: .semibold))

                Button(role: .destructive) {
                    viewModel.removeRoute(id: route.wrappedValue.id)
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }

            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 8) {
                GridRow {
                    Text("ID")
                        .foregroundStyle(.secondary)
                    TextField("route-id", text: route.id)
                        .textFieldStyle(.roundedBorder)
                }

                GridRow {
                    Text("Kind")
                        .foregroundStyle(.secondary)
                    Picker("Kind", selection: route.kind) {
                        Text("App").tag("app")
                        Text("Tmux").tag("tmux")
                        Text("Clipboard").tag("clipboard")
                        Text("Auto").tag("automatic")
                    }
                    .labelsHidden()
                    .frame(width: 150)
                }

                GridRow {
                    Text("Target")
                        .foregroundStyle(.secondary)
                    TextField("Target app or tmux target", text: optionalBinding(route.target))
                        .textFieldStyle(.roundedBorder)
                }

                GridRow {
                    Text("Shortcut")
                        .foregroundStyle(.secondary)
                    TextField("Optional", text: optionalBinding(route.shortcut))
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 120)
                }
            }
        }
        .padding(14)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func sectionHeader(_ title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.title2.weight(.semibold))

            Text(subtitle)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func readinessRow(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.headline)

            Text(text)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func setupWizardRow(_ number: String, _ title: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(number)
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(Color.accentColor, in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))

                Text(text)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func settingsStatusRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(width: 92, alignment: .leading)

            Text(value.isEmpty ? "-" : value)
                .textSelection(.enabled)
                .lineLimit(2)
        }
        .font(.caption)
    }

    private func optionalBinding(_ binding: Binding<String?>) -> Binding<String> {
        Binding(
            get: { binding.wrappedValue ?? "" },
            set: { binding.wrappedValue = $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 }
        )
    }
}
