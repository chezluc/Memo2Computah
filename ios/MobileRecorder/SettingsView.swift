import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var viewModel: RecordingViewModel
    @EnvironmentObject private var dropboxManager: DropboxSessionManager
    @State private var showFolderPicker = false

    var body: some View {
        NavigationStack {
            List {
                Section("Dropbox") {
                    HStack {
                        Text("Status")
                        Spacer()
                        Text(dropboxManager.isLinked ? "Connected" : "Not connected")
                            .foregroundStyle(dropboxManager.isLinked ? .green : .secondary)
                    }

                    if let accountName = dropboxManager.accountName, dropboxManager.isLinked {
                        HStack {
                            Text("Account")
                            Spacer()
                            Text(accountName)
                                .foregroundStyle(.secondary)
                        }
                    }

                    if let authError = dropboxManager.authErrorMessage {
                        Text(authError)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }

                    if dropboxManager.isLinked {
                        Button("Choose Default Folder") {
                            showFolderPicker = true
                        }
                        .accessibilityIdentifier("chooseDefaultFolderButton")

                        HStack {
                            Text("Folder")
                            Spacer()
                            Text(dropboxManager.defaultFolderPath)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.trailing)
                        }

                        Button("Disconnect Dropbox", role: .destructive) {
                            dropboxManager.unlink()
                        }
                        .accessibilityIdentifier("disconnectDropboxButton")
                    } else {
                        Button("Connect Dropbox") {
                            dropboxManager.connect()
                        }
                        .accessibilityIdentifier("connectDropboxButton")
                    }
                }

                Section("Behavior") {
                    Picker("Screen 0 transcription", selection: $viewModel.normalTranscriptionMode) {
                        ForEach(RecordingViewModel.NormalTranscriptionMode.allCases) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }
                    .accessibilityIdentifier("normalTranscriptionModePicker")

                    Text(viewModel.normalTranscriptionMode.detail)
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    Toggle("Show live transcript while recording", isOn: $viewModel.liveTranscriptPreviewEnabled)
                        .accessibilityIdentifier("liveTranscriptPreviewToggle")

                    Text("In Dropbox audio mode this is only a preview. In Apple Speech mode the shown transcript is the text sent to Dropbox for routing.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    Text("The selected Dropbox folder remains the drop zone. Audio mode sends recordings; Apple Speech mode sends text jobs. The Mac companion watches the folder and applies the selected route.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("Routes") {
                    HStack {
                        Text("Selected")
                        Spacer()
                        Text(viewModel.effectiveRouteLabel)
                            .foregroundStyle(.secondary)
                    }

                    Toggle("Show route selector", isOn: $viewModel.showRouteSelectorOnRecorder)
                        .accessibilityIdentifier("showRouteSelectorToggle")

                    Toggle("Show route buttons", isOn: $viewModel.showRouteButtonsOnRecorder)
                        .accessibilityIdentifier("showRouteButtonsToggle")

                    if viewModel.showRouteButtonsOnRecorder {
                        HStack {
                            Button("Select All Routes") {
                                viewModel.selectAllQuickRoutes()
                            }
                            .accessibilityIdentifier("selectAllQuickRoutesButton")

                            Spacer()

                            Button("Reset Quick Menu") {
                                viewModel.resetQuickRoutesToDefaults()
                            }
                            .accessibilityIdentifier("resetQuickRoutesButton")
                        }
                    }

                    ForEach(RecordingViewModel.RouteTarget.allCases) { route in
                        Toggle(isOn: quickRouteToggleBinding(route: route)) {
                            HStack {
                                Text(route.label)
                                Spacer()
                                Text(route.metadataValue ?? "auto")
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .accessibilityIdentifier("quickRouteToggle-\(route.rawValue)")
                    }

                    Text("Show the route selector, the route button row, or both. Use the switches beside each route to add or remove it from the quick menu. Select all routes to make the quick row show every route.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("How It Works") {
                    Label("The iPhone uploads either recorded audio or an Apple Speech text job to Dropbox.", systemImage: "1.circle")
                    Label("The Mac companion starts and monitors the watcher.", systemImage: "2.circle")
                    Label("The watcher transcribes, copies text, and routes it to the selected app.", systemImage: "3.circle")

                    Text("For App Store release, Dropbox setup and Mac companion setup should be shown as first-run onboarding so users understand that the iPhone and Mac work as a pair.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .accessibilityIdentifier("settingsDoneButton")
                }
            }
            .sheet(isPresented: $showFolderPicker) {
                DropboxFolderBrowserView(selectedPath: $dropboxManager.defaultFolderPath)
                    .environmentObject(dropboxManager)
            }
            .task {
                if dropboxManager.isLinked && dropboxManager.accountName == nil {
                    await dropboxManager.refreshAccountName()
                }
            }
            .onChange(of: dropboxManager.defaultFolderPath) { _, _ in
                dropboxManager.persistDefaultFolder()
            }
            .onChange(of: viewModel.liveTranscriptPreviewEnabled) { _, _ in
                viewModel.persistLiveTranscriptPreviewEnabled()
            }
            .onChange(of: viewModel.normalTranscriptionMode) { _, _ in
                viewModel.persistNormalTranscriptionMode()
            }
            .onChange(of: viewModel.showRouteSelectorOnRecorder) { _, _ in
                viewModel.persistShowRouteSelectorOnRecorder()
            }
            .onChange(of: viewModel.showRouteButtonsOnRecorder) { _, _ in
                viewModel.persistShowRouteButtonsOnRecorder()
            }
        }
    }

    private func quickRouteToggleBinding(route: RecordingViewModel.RouteTarget) -> Binding<Bool> {
        Binding {
            viewModel.isQuickRouteTarget(route)
        } set: { isIncluded in
            viewModel.setQuickRouteTarget(route, isIncluded: isIncluded)
        }
    }
}

struct DropboxFolderBrowserView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var dropboxManager: DropboxSessionManager
    @Binding var selectedPath: String

    @State private var currentPath: String
    @State private var folders: [DropboxFolderEntry] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    init(selectedPath: Binding<String>) {
        self._selectedPath = selectedPath
        self._currentPath = State(initialValue: selectedPath.wrappedValue)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        selectedPath = currentPath
                        dropboxManager.persistDefaultFolder()
                        dismiss()
                    } label: {
                        HStack {
                            Text("Use This Folder")
                            Spacer()
                            Text(displayPath(currentPath))
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if currentPath != "/" {
                    Section {
                        Button("Up One Level") {
                            currentPath = parentPath(for: currentPath)
                            Task { await loadFolders() }
                        }
                    }
                }

                Section("Folders") {
                    if isLoading {
                        ProgressView()
                            .frame(maxWidth: .infinity, alignment: .center)
                    } else if let errorMessage {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    } else {
                        ForEach(folders) { folder in
                            Button {
                                currentPath = folder.path
                                Task { await loadFolders() }
                            } label: {
                                HStack {
                                    Image(systemName: "folder")
                                    Text(folder.name)
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .foregroundStyle(.tertiary)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle(displayPath(currentPath))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .task {
                await loadFolders()
            }
        }
    }

    private func loadFolders() async {
        isLoading = true
        errorMessage = nil
        do {
            folders = try await dropboxManager.listFolders(at: currentPath)
        } catch {
            folders = []
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func displayPath(_ path: String) -> String {
        path == "/" ? "Dropbox" : path
    }

    private func parentPath(for path: String) -> String {
        let normalized = path == "/" ? "/" : path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !normalized.isEmpty, let slash = normalized.lastIndex(of: "/") else { return "/" }
        let parent = String(normalized[..<slash])
        return parent.isEmpty ? "/" : "/" + parent
    }
}
