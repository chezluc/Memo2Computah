import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var viewModel: RecordingViewModel
    @EnvironmentObject private var dropboxManager: DropboxSessionManager
    @State private var showFolderPicker = false
    @State private var showGoogleDriveFolderPicker = false

    var body: some View {
        NavigationStack {
            List {
                Section("Delivery") {
                    deliveryModePicker
                    receiverStatus
                    lanDeliveryControls
                    googleDriveDeliveryControls
                    cloudflareDeliveryControls
                    httpReceiverControls
                }

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

                Section("Google Drive") {
                    HStack {
                        Text("Status")
                        Spacer()
                        Text(viewModel.googleDriveFolderIsReady ? "Connected" : "Not connected")
                            .foregroundStyle(viewModel.googleDriveFolderIsReady ? .green : .secondary)
                    }

                    HStack {
                        Text("Folder")
                        Spacer()
                        Text(viewModel.googleDriveFolderDisplayName)
                            .foregroundColor(viewModel.googleDriveFolderIsReady ? .secondary : .orange)
                            .multilineTextAlignment(.trailing)
                    }

                    if let googleDriveFolderError = viewModel.googleDriveFolderError {
                        Text(googleDriveFolderError)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }

                    if viewModel.googleDriveFolderIsReady {
                        Button("Choose Different Folder") {
                            showGoogleDriveFolderPicker = true
                        }
                        .accessibilityIdentifier("chooseGoogleDriveFolderButton")

                        Button("Disconnect Google Drive", role: .destructive) {
                            viewModel.clearGoogleDriveFolder()
                        }
                        .accessibilityIdentifier("disconnectGoogleDriveButton")
                    } else {
                        Button("Connect Google Drive") {
                            viewModel.deliveryMode = .googleDriveFiles
                            viewModel.persistDeliveryMode()
                            showGoogleDriveFolderPicker = true
                        }
                        .accessibilityIdentifier("connectGoogleDriveButton")
                    }

                    Text("This uses the Google Drive location in the iPhone Files app. Install Google Drive, enable it in Files, then choose the `auto.transcribe` folder.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
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

                    Text("In audio mode this is only a preview. In Apple Speech mode the shown transcript is sent through the selected delivery mode for routing.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    Text("Audio mode sends recordings; Apple Speech mode sends text jobs. Memo2Computah Desktop receives or watches the delivery target and applies the selected route.")
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
                    Label("The iPhone sends recorded audio or an Apple Speech text job through the selected delivery mode.", systemImage: "1.circle")
                    Label("Memo2Computah Desktop receives LAN/Cloudflare uploads or watches Dropbox.", systemImage: "2.circle")
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
            .fileImporter(
                isPresented: $showGoogleDriveFolderPicker,
                allowedContentTypes: [.folder],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    guard let folderURL = urls.first else { return }
                    viewModel.setGoogleDriveFolder(url: folderURL)
                case .failure:
                    break
                }
            }
            .task {
                if dropboxManager.isLinked && dropboxManager.accountName == nil {
                    await dropboxManager.refreshAccountName()
                }
            }
            .onChange(of: dropboxManager.defaultFolderPath) { _, _ in
                dropboxManager.persistDefaultFolder()
            }
            .onChange(of: viewModel.deliveryMode) { _, _ in
                viewModel.persistDeliveryMode()
            }
            .onChange(of: viewModel.serverURLString) { _, _ in
                viewModel.persistServerURL()
            }
            .onChange(of: viewModel.cloudflareServerURLString) { _, _ in
                viewModel.persistCloudflareServerURL()
            }
            .onChange(of: viewModel.directTextAPIToken) { _, _ in
                viewModel.persistDirectTextSettings()
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

    private var deliveryModePicker: some View {
        Group {
            Picker("Mode", selection: $viewModel.deliveryMode) {
                ForEach(RecordingViewModel.DeliveryMode.allCases) { mode in
                    Text(mode.label).tag(mode)
                }
            }
            .accessibilityIdentifier("deliveryModePicker")

            Text(viewModel.deliveryMode.detail)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var receiverStatus: some View {
        Group {
            HStack {
                Text("Receiver")
                Spacer()
                Text(viewModel.receiverReachability.label)
                    .foregroundStyle(receiverReachabilityColor)
            }

            Text(viewModel.receiverReachability.detail)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
    }

    @ViewBuilder
    private var lanDeliveryControls: some View {
        if viewModel.deliveryMode == .lanHTTP {
            Picker("LAN receiver", selection: selectedLANReceiverBinding) {
                ForEach(viewModel.lanReceiverProfiles) { profile in
                    Text(profile.name).tag(profile.id)
                }
            }
            .accessibilityIdentifier("lanReceiverPicker")

            Button("Add LAN Receiver") {
                viewModel.addLANReceiverProfile()
            }
            .accessibilityIdentifier("addLANReceiverButton")

            TextField("LAN receiver URL", text: $viewModel.serverURLString)
                .textInputAutocapitalization(.never)
                .keyboardType(.URL)
                .autocorrectionDisabled()
                .accessibilityIdentifier("lanReceiverURLField")

            Text("Use the exact LAN URL shown in Memo2Computah Desktop. On the current Wi-Fi, that should look like `\(RecordingViewModel.defaultLANServerURLString)`.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var googleDriveDeliveryControls: some View {
        if viewModel.deliveryMode == .googleDriveFiles {
            Button("Check Folder") {
                Task { await viewModel.checkSelectedReceiver() }
            }
            .accessibilityIdentifier("checkGoogleDriveFolderButton")

            Text(viewModel.googleDriveFolderIsReady ? "Google Drive is connected to `\(viewModel.googleDriveFolderDisplayName)`." : "Connect Google Drive below before recording in this mode.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var cloudflareDeliveryControls: some View {
        if viewModel.deliveryMode == .cloudflareHTTP {
            TextField("Cloudflare tunnel URL", text: $viewModel.cloudflareServerURLString)
                .textInputAutocapitalization(.never)
                .keyboardType(.URL)
                .autocorrectionDisabled()
                .accessibilityIdentifier("cloudflareReceiverURLField")

            Text("Use the public Cloudflare tunnel URL that forwards to the Memo2Computah Desktop receiver.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 6) {
                Text("Cloudflare quick setup")
                    .font(.footnote.weight(.semibold))

                Text("Start the receiver in Memo2Computah Desktop, then run a tunnel to the local receiver port. Use the resulting `https://...trycloudflare.com` URL here.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Text("cloudflared tunnel --url http://127.0.0.1:8943")
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
            }
        }
    }

    @ViewBuilder
    private var httpReceiverControls: some View {
        if viewModel.deliveryMode == .lanHTTP || viewModel.deliveryMode == .cloudflareHTTP {
            SecureField("Receiver API token", text: $viewModel.directTextAPIToken)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .accessibilityIdentifier("receiverAPITokenField")

            Text("Use the same token shown in Memo2Computah Desktop. This protects LAN and Cloudflare uploads.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            Button("Check Receiver") {
                Task { await viewModel.checkSelectedReceiver() }
            }
            .disabled(viewModel.receiverReachability == .checking)
            .accessibilityIdentifier("checkReceiverButton")
        }
    }

    private func quickRouteToggleBinding(route: RecordingViewModel.RouteTarget) -> Binding<Bool> {
        Binding {
            viewModel.isQuickRouteTarget(route)
        } set: { isIncluded in
            viewModel.setQuickRouteTarget(route, isIncluded: isIncluded)
        }
    }

    private var selectedLANReceiverBinding: Binding<String> {
        Binding {
            viewModel.selectedLANReceiverID
        } set: { receiverID in
            viewModel.selectLANReceiver(id: receiverID)
        }
    }

    private var receiverReachabilityColor: Color {
        switch viewModel.receiverReachability {
        case .ready:
            return .green
        case .offline:
            return .red
        case .checking:
            return .orange
        case .notChecked:
            return .secondary
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
