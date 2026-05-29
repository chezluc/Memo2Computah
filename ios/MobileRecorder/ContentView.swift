import SwiftUI
import UIKit

struct ContentView: View {
    private enum AppScreen {
        case recorder
        case conversation
        case call
    }

    @StateObject private var viewModel = RecordingViewModel()
    @EnvironmentObject private var dropboxManager: DropboxSessionManager
    @EnvironmentObject private var launchCoordinator: RecordingLaunchCoordinator
    @Environment(\.scenePhase) private var scenePhase
    @State private var showSettings = false
    @State private var showRoutePicker = false
    @State private var typedMessage = ""
    @State private var selectedScreen: AppScreen = .recorder

    private var topSafeAreaAdjustment: CGFloat {
        Self.launchAdjustment(named: "TOP_SAFE_ADJUST")
    }

    private var bottomSafeAreaAdjustment: CGFloat {
        Self.launchAdjustment(named: "BOTTOM_SAFE_ADJUST")
    }

    private var contentVerticalAdjustment: CGFloat {
        Self.launchAdjustment(named: "CONTENT_VERTICAL_ADJUST")
    }

    var body: some View {
        GeometryReader { geometry in
            let settingsY = 88 + topSafeAreaAdjustment
            let recorderY = (geometry.size.height * 0.365) + contentVerticalAdjustment
            let bottomPanelY = (geometry.size.height * 0.635) + bottomSafeAreaAdjustment
            let normalTranscriptY = 174 + topSafeAreaAdjustment
            let normalTranscriptWidth = min(geometry.size.width - 112, 300)

            ZStack {
                Color.black
                    .ignoresSafeArea()

                recorderBody
                    .frame(width: geometry.size.width - 44)
                    .position(
                        x: geometry.size.width / 2,
                        y: recorderY
                    )

                normalLiveTranscriptPanel
                    .frame(width: normalTranscriptWidth)
                    .position(x: geometry.size.width / 2, y: normalTranscriptY)

                bottomPanel
                    .frame(width: geometry.size.width - 32)
                    .position(
                        x: geometry.size.width / 2,
                        y: bottomPanelY
                    )

                settingsButton
                    .position(x: geometry.size.width - 27, y: settingsY)

                if showRoutePicker {
                    routePickerOverlay
                }
            }
        }
        .ignoresSafeArea(.all)
        .preferredColorScheme(.dark)
        .onDisappear {
            viewModel.persistServerURL()
            viewModel.persistSubmitAfterPaste()
            viewModel.persistRouteTarget()
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .environmentObject(viewModel)
                .environmentObject(dropboxManager)
        }
        .task {
            await triggerAutoStartIfNeeded()
        }
        .onChange(of: launchCoordinator.autoStartNonce) { _, _ in
            Task { await triggerAutoStartIfNeeded() }
        }
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .active:
                Task {
                    await viewModel.handleSceneBecameActive()
                }
            case .background:
                viewModel.handleSceneMovedFromActive()
            case .inactive:
                break
            @unknown default:
                break
            }
        }
    }

    private var isConversationLayout: Bool {
        selectedScreen == .conversation
    }

    private var isCallLayout: Bool {
        selectedScreen == .call
    }

    private func triggerAutoStartIfNeeded() async {
        guard launchCoordinator.consumePendingAutoStart() else { return }
        await viewModel.startRecordingFromExternalTrigger()
    }

    private var settingsButton: some View {
        Button {
            showSettings = true
        } label: {
            Image(systemName: "gearshape.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white.opacity(0.88))
                .frame(width: 34, height: 34)
                .background(Color.white.opacity(0.06), in: Circle())
                .overlay(
                    Circle().stroke(Color.white.opacity(0.12), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("settingsButton")
    }

    private var topControls: some View {
        HStack(spacing: 8) {
            Spacer()
            settingsButton
        }
    }

    // MARK: - Recorder body

    private var recorderBody: some View {
        VStack(spacing: 14) {
            waveform

            Text(formattedTime(viewModel.elapsedSeconds))
                .font(.system(size: 52, weight: .regular, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)

            Text(statusLine)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(statusColor)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        }
        .accessibilityIdentifier("recorderBody")
    }

    @ViewBuilder
    private var normalLiveTranscriptPanel: some View {
        let transcript = viewModel.liveTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        let shouldShowTranscript = viewModel.liveTranscriptPreviewEnabled || viewModel.normalTranscriptionMode == .appleSpeechOnDevice
        if shouldShowTranscript && !transcript.isEmpty {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(transcript)
                            .font(.system(size: 15, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(0.82))
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 2)
                            .padding(.vertical, 4)

                        Color.clear
                            .frame(height: 1)
                            .id("normalTranscriptBottom")
                    }
                }
                .scrollIndicators(.visible)
                .onChange(of: viewModel.liveTranscript) { _, _ in
                    withAnimation(.easeOut(duration: 0.16)) {
                        proxy.scrollTo("normalTranscriptBottom", anchor: .bottom)
                    }
                }
            }
            .frame(maxHeight: 82, alignment: .top)
            .contentShape(Rectangle())
            .accessibilityIdentifier("normalLiveTranscriptPanel")
        }
    }

    private var bottomPanel: some View {
        VStack(spacing: 16) {
            transportControls
            if viewModel.showRouteSelectorOnRecorder {
                routeSelector
            }
            if viewModel.showRouteButtonsOnRecorder {
                favoriteRouteButtons
            }
        }
        .accessibilityIdentifier("bottomPanel")
    }

    private var modeMenuBar: some View {
        HStack(spacing: 0) {
            modeMenuButton(.recorder)
            modeMenuButton(.conversation)
            modeMenuButton(.call)
        }
        .frame(width: 292, height: 52)
        .background(Color.black.opacity(0.92), in: Capsule())
        .overlay(
            Capsule()
                .stroke(Color.white.opacity(0.10), lineWidth: 1)
        )
        .accessibilityIdentifier("modeMenuBar")
    }

    private func modeMenuButton(_ screen: AppScreen) -> some View {
        Button {
            handleModeTap(screen)
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(modeMenuFill(for: screen))
                    .frame(width: 70, height: 34)

                HStack(spacing: screen == .recorder ? 5 : 0) {
                    Image(systemName: modeMenuIcon(for: screen))
                        .font(.system(size: modeMenuIconSize(for: screen), weight: .semibold))

                    if screen == .recorder {
                        miniAudioBars
                    }
                }
                .foregroundStyle(modeMenuForeground(for: screen))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(modeMenuAccessibilityID(for: screen))
    }

    private var miniAudioBars: some View {
        HStack(spacing: 2) {
            ForEach([5.0, 11.0, 7.0], id: \.self) { height in
                Capsule()
                    .fill(Color.white.opacity(0.60))
                    .frame(width: 2, height: height)
            }
        }
    }

    private func modeMenuFill(for screen: AppScreen) -> Color {
        switch screen {
        case .recorder:
            return selectedScreen == .recorder ? Color.clear : Color.clear
        case .conversation:
            return selectedScreen == .conversation ? Color.white.opacity(0.16) : Color.clear
        case .call:
            return selectedScreen == .call ? Color.red : Color.black.opacity(0.68)
        }
    }

    private func modeMenuForeground(for screen: AppScreen) -> Color {
        if screen == .call, selectedScreen == .call {
            return .white
        }
        return .white.opacity(selectedScreen == screen ? 0.92 : 0.68)
    }

    private func modeMenuIcon(for screen: AppScreen) -> String {
        switch screen {
        case .recorder:
            return "microphone.fill"
        case .conversation:
            return "ellipsis.message.fill"
        case .call:
            return selectedScreen == .call ? "phone.down.fill" : "phone.fill"
        }
    }

    private func modeMenuIconSize(for screen: AppScreen) -> CGFloat {
        switch screen {
        case .recorder:
            return 12
        case .conversation:
            return 16
        case .call:
            return 15
        }
    }

    private func modeMenuAccessibilityID(for screen: AppScreen) -> String {
        switch screen {
        case .recorder:
            return "modeRecorderButton"
        case .conversation:
            return "modeConversationButton"
        case .call:
            return "modeCallButton"
        }
    }

    private func handleModeTap(_ screen: AppScreen) {
        switch screen {
        case .recorder:
            withAnimation(.spring(response: 0.26, dampingFraction: 0.86)) {
                selectedScreen = .recorder
            }
            viewModel.openRecorderView()
        case .conversation:
            withAnimation(.spring(response: 0.26, dampingFraction: 0.86)) {
                selectedScreen = .conversation
            }
            viewModel.openTextThreadView()
        case .call:
            withAnimation(.spring(response: 0.26, dampingFraction: 0.86)) {
                selectedScreen = .call
            }
            Task {
                await viewModel.openCallViewAndStart()
            }
        }
    }

    private var messageThreadPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: viewModel.isWaitingForTextResponse ? "ellipsis.message.fill" : "message.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white.opacity(0.55))

                Text(viewModel.isWaitingForTextResponse ? "Waiting for reply" : "Message thread")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.48))

                Spacer()
            }

            if viewModel.threadMessages.isEmpty {
                Text("Text replies will appear here.")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.34))
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(viewModel.threadMessages.suffix(3)) { message in
                        threadBubble(message, compact: true)
                    }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, minHeight: 88, maxHeight: 132, alignment: .topLeading)
        .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
        .accessibilityIdentifier("messageThreadPanel")
    }

    private var conversationBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(viewModel.threadMessages) { message in
                            threadBubble(message, compact: false)
                                .id(message.id)
                        }
                        liveTranscriptBubble(compact: false)
                            .id("liveTranscript")
                    }
                    .frame(maxWidth: .infinity, alignment: .bottomLeading)
                    .padding(.top, 148)
                    .padding(.bottom, 18)
                    .padding(.horizontal, 14)
                }
                .scrollIndicators(.hidden)
                .onChange(of: viewModel.threadMessages.count) { _, _ in
                    if let last = viewModel.threadMessages.last {
                        withAnimation(.easeOut(duration: 0.22)) {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
                .onChange(of: viewModel.liveTranscript) { _, transcript in
                    if !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        withAnimation(.easeOut(duration: 0.22)) {
                            proxy.scrollTo("liveTranscript", anchor: .bottom)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())

            conversationRecordingStatus
            typedMessageComposer
                .padding(.horizontal, 16)
                .padding(.bottom, 92)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityIdentifier("conversationBody")
    }

    private var conversationHeader: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text("WezTerm")
                    .font(.system(size: 24, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)

                Text(conversationSubtitle)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(statusColor.opacity(0.82))
            }

            Spacer()

            voiceCallToggle
            textResponseToggle
            settingsButton
        }
        .padding(.top, 58)
        .padding(.horizontal, 16)
        .padding(.bottom, 14)
        .background(Color.black.opacity(0.94))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.white.opacity(0.08))
                .frame(height: 1)
        }
    }

    private var conversationSubtitle: String {
        if viewModel.isWaitingForTextResponse {
            return "Waiting for reply from \(viewModel.effectiveRouteLabel)"
        }
        if viewModel.callSessionActive {
            return "Listening and sending turns to \(viewModel.effectiveRouteLabel)"
        }
        return "Text thread routed to \(viewModel.effectiveRouteLabel)"
    }

    private var conversationEmptyState: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Start talking or type below. Your transcript and the computer response will appear as messages.")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.white.opacity(0.62))
                .fixedSize(horizontal: false, vertical: true)

            Text("For the first test, use WezTerm with the `voice_return` tmux session.")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.36))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 24)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var conversationRecordingStatus: some View {
        if viewModel.state == .recording || viewModel.state == .paused || viewModel.state == .uploading {
            HStack(spacing: 10) {
                Circle()
                    .fill(viewModel.state == .uploading ? Color.blue : Color.red)
                    .frame(width: 8, height: 8)

                Text(conversationRecordingLabel)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.78))

                Spacer()

                if viewModel.state == .recording || viewModel.state == .paused {
                    Button(primaryButtonLabel) {
                        viewModel.togglePause()
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.72))

                    Button("Cancel") {
                        viewModel.cancelRecording()
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.red.opacity(0.86))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color.white.opacity(0.07), in: Capsule())
            .padding(.horizontal, 12)
            .padding(.bottom, 10)
        }
    }

    private var conversationRecordingLabel: String {
        switch viewModel.state {
        case .recording:
            return "Recording \(formattedTime(viewModel.elapsedSeconds))"
        case .paused:
            return "Paused \(formattedTime(viewModel.elapsedSeconds))"
        case .uploading:
            return "Uploading voice message"
        case .idle:
            return ""
        }
    }

    private var typedMessageComposer: some View {
        HStack(alignment: .bottom, spacing: 10) {
            TextField("Type a message", text: $typedMessage, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.white)
                .lineLimit(1...4)
                .submitLabel(.send)
                .onSubmit {
                    sendTypedMessage()
                }
                .padding(.horizontal, 13)
                .padding(.vertical, 10)
                .background(Color.black.opacity(0.34), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )

            if canSendTypedMessage {
                Button {
                    sendTypedMessage()
                } label: {
                    Image(systemName: "paperplane.fill")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.black)
                        .frame(width: 40, height: 40)
                        .background(Color.white, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("typedMessageSendButton")
            }
        }
        .accessibilityIdentifier("typedMessageComposer")
    }

    private var canSendTypedMessage: Bool {
        !typedMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var chatRecordButton: some View {
        Button {
            Task {
                await viewModel.toggleRecording()
            }
        } label: {
            ZStack {
                Circle()
                    .fill(chatRecordButtonBackground)
                    .frame(width: 40, height: 40)

                if viewModel.state == .uploading {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.white)
                } else {
                    Image(systemName: chatRecordButtonSymbol)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(viewModel.state == .uploading)
        .accessibilityIdentifier("chatRecordButton")
    }

    private var chatRecordButtonSymbol: String {
        switch viewModel.state {
        case .recording: return "stop.fill"
        case .paused: return "play.fill"
        case .uploading: return "arrow.up"
        case .idle: return "mic.fill"
        }
    }

    private var chatRecordButtonBackground: Color {
        switch viewModel.state {
        case .recording: return .red
        case .paused: return .yellow.opacity(0.88)
        case .uploading: return .blue.opacity(0.72)
        case .idle: return .red.opacity(0.82)
        }
    }

    private var callBody: some View {
        GeometryReader { geometry in
            ZStack {
                callVoiceOrb
                    .frame(width: min(geometry.size.width * 0.74, 280), height: 260)
                    .position(x: geometry.size.width / 2, y: geometry.size.height * 0.43)

                callLiveTranscriptText
                    .frame(width: geometry.size.width - 64)
                    .position(x: geometry.size.width / 2, y: geometry.size.height * 0.60)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .onTapGesture {
                viewModel.stopSpokenCallResponse(restartListening: true)
            }
        }
        .onAppear {
            viewModel.setCallViewVisible(true)
            ensureCallIsListening()
        }
        .onChange(of: viewModel.voiceCallModeEnabled) { _, _ in
            ensureCallIsListening()
        }
        .onChange(of: viewModel.callSessionActive) { _, _ in
            ensureCallIsListening()
        }
        .onChange(of: viewModel.state) { _, _ in
            ensureCallIsListening()
        }
        .onDisappear {
            viewModel.setCallViewVisible(false)
        }
        .accessibilityIdentifier("callBody")
    }

    @ViewBuilder
    private var callLiveTranscriptText: some View {
        let transcript = viewModel.liveTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        if !transcript.isEmpty {
            Text(transcript)
                .font(.system(size: 20, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.86))
                .multilineTextAlignment(.center)
                .lineLimit(4)
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier("callLiveTranscriptText")
        }
    }

    private var callTurnComposer: some View {
        HStack(spacing: 12) {
            HStack(spacing: 8) {
                Circle()
                    .fill(callStatusColor.opacity(0.9))
                    .frame(width: 8, height: 8)

                Text(callComposerStatus)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.62))
            }

            Spacer()

            Button {
                viewModel.toggleSpeakCallResponses()
            } label: {
                Image(systemName: viewModel.speakCallResponsesEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(viewModel.speakCallResponsesEnabled ? .black : .white.opacity(0.48))
                    .frame(width: 44, height: 44)
                    .background(viewModel.speakCallResponsesEnabled ? Color.white.opacity(0.9) : Color.white.opacity(0.08), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("speakCallResponsesToggle")

            Button {
                guard canSendCallTurn else { return }
                Task {
                    await viewModel.sendCurrentCallTurnNow()
                }
            } label: {
                HStack(spacing: 7) {
                    Text("Send turn")
                        .font(.system(size: 15, weight: .semibold))

                    Image(systemName: "paperplane.fill")
                        .font(.system(size: 13, weight: .bold))
                }
                .foregroundStyle(canSendCallTurn ? .black : .white.opacity(0.42))
                .padding(.horizontal, 16)
                .frame(height: 44)
                .background(canSendCallTurn ? Color.green : Color.white.opacity(0.08), in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(!canSendCallTurn)
            .accessibilityIdentifier("callSendTurnButton")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color.white.opacity(0.06), in: Capsule())
        .overlay(
            Capsule()
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    private var callComposerStatus: String {
        if viewModel.isWaitingForCallResponse {
            return "Thinking"
        }

        switch viewModel.state {
        case .recording:
            return "Listening"
        case .uploading:
            return "Sending"
        case .paused:
            return "Paused"
        case .idle:
            return viewModel.voiceCallModeEnabled || viewModel.callSessionActive ? "Listening" : "Ready"
        }
    }

    private func ensureCallIsListening() {
        guard viewModel.voiceCallModeEnabled,
              !viewModel.callSessionActive,
              viewModel.state == .idle
        else { return }

        Task {
            await viewModel.startVoiceCallSession()
        }
    }

    private var callVoiceOrb: some View {
        Button {
            guard canSendCallTurn else { return }
            Task {
                await viewModel.sendCurrentCallTurnNow()
            }
        } label: {
            TimelineView(.animation) { timeline in
                let time = timeline.date.timeIntervalSinceReferenceDate
                callVoiceVisual(time: time)
            }
        }
        .buttonStyle(.plain)
        .disabled(!canSendCallTurn)
        .accessibilityIdentifier("callVoiceOrb")
        .accessibilityLabel(canSendCallTurn ? "Send turn" : "Call status")
    }

    @ViewBuilder
    private func callVoiceVisual(time: TimeInterval) -> some View {
        if viewModel.isWaitingForCallResponse || viewModel.state == .uploading {
            callSeedCluster(time: time)
        } else {
            callVoiceBars(time: time)
        }
    }

    private func callVoiceBars(time: TimeInterval) -> some View {
        HStack(spacing: 12) {
            ForEach(0..<5, id: \.self) { index in
                Capsule()
                    .fill(callVisualColor.opacity(callBarOpacity(index: index, time: time)))
                    .frame(width: 22, height: callBarHeight(index: index, time: time))
                    .animation(.easeOut(duration: 0.08), value: viewModel.waveformSamples)
            }
        }
        .frame(width: 220, height: 220)
        .contentShape(Rectangle())
    }

    private func callSeedCluster(time: TimeInterval) -> some View {
        ZStack {
            ForEach(0..<7, id: \.self) { index in
                let phase = time * (viewModel.isWaitingForCallResponse ? 2.2 : 1.55) + Double(index) * 0.7
                let angle = (Double(index) / 7.0 * .pi * 2.0) + time * 0.28
                let radius = CGFloat(34 + sin(phase) * 8)
                let size = CGFloat(13 + ((sin(phase + 0.9) + 1.0) * 4))

                Circle()
                    .fill(callVisualColor.opacity(0.42 + ((sin(phase) + 1.0) * 0.18)))
                    .frame(width: size, height: size)
                    .offset(
                        x: CGFloat(cos(angle)) * radius,
                        y: CGFloat(sin(angle)) * radius
                    )
            }

            Circle()
                .fill(callVisualColor.opacity(0.72))
                .frame(width: 28, height: 28)
        }
        .frame(width: 220, height: 220)
        .contentShape(Rectangle())
    }

    private func callBarHeight(index: Int, time: TimeInterval) -> CGFloat {
        let samples = viewModel.waveformSamples
        let stride = max(1, samples.count / 5)
        let sampleIndex = samples.isEmpty ? 0 : min(samples.count - 1, index * stride)
        let sampleLevel = samples.isEmpty ? CGFloat(0.08) : samples[sampleIndex]
        let ambientPulse = CGFloat((sin(time * 4.8 + Double(index) * 0.85) + 1.0) / 2.0)
        let level: CGFloat

        if viewModel.state == .recording {
            level = max(sampleLevel, ambientPulse * 0.32)
        } else if viewModel.state == .paused {
            level = 0.14
        } else {
            level = ambientPulse * 0.18
        }

        return 32 + min(1.0, level) * 124
    }

    private func callBarOpacity(index: Int, time: TimeInterval) -> Double {
        if viewModel.state == .recording {
            return 0.50 + ((sin(time * 3.2 + Double(index)) + 1.0) * 0.18)
        }
        return 0.24
    }

    private var callVisualColor: Color {
        if viewModel.isWaitingForCallResponse {
            return .blue
        }

        switch viewModel.state {
        case .recording:
            return .green
        case .uploading:
            return .orange
        case .paused:
            return .yellow
        case .idle:
            return viewModel.callSessionActive || viewModel.voiceCallModeEnabled ? .green : .white
        }
    }

    @ViewBuilder
    private func liveTranscriptCaption(maxLines: Int) -> some View {
        let transcript = viewModel.liveTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        if !transcript.isEmpty {
            Text(transcript)
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.82))
                .multilineTextAlignment(.center)
                .lineLimit(maxLines)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity)
                .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.white.opacity(0.09), lineWidth: 1)
                )
                .accessibilityIdentifier("liveTranscriptCaption")
        }
    }

    @ViewBuilder
    private func liveTranscriptBubble(compact: Bool) -> some View {
        let transcript = viewModel.liveTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        if !transcript.isEmpty {
            HStack {
                Spacer(minLength: compact ? 22 : 46)

                Text(transcript)
                    .font(.system(size: compact ? 12 : 15, weight: .medium))
                    .foregroundStyle(.black.opacity(0.82))
                    .lineLimit(compact ? 3 : nil)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: compact ? .infinity : 280, alignment: .leading)
                    .padding(.horizontal, compact ? 10 : 14)
                    .padding(.vertical, compact ? 7 : 10)
                    .background(Color.white.opacity(0.82), in: RoundedRectangle(cornerRadius: compact ? 12 : 18, style: .continuous))
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .accessibilityIdentifier("liveTranscriptBubble")
        }
    }

    private var callHeader: some View {
        HStack(alignment: .center, spacing: 10) {
            Spacer()
            settingsButton
        }
        .padding(.top, 58)
        .padding(.horizontal, 16)
        .padding(.bottom, 14)
        .background(Color.black.opacity(0.94))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.white.opacity(0.08))
                .frame(height: 1)
        }
    }

    private var callPhaseTitle: String {
        if viewModel.isWaitingForCallResponse {
            return "Thinking"
        }

        switch viewModel.state {
        case .recording:
            return "Listening"
        case .uploading:
            return "Sending"
        case .paused:
            return "Paused"
        case .idle:
            return viewModel.voiceCallModeEnabled || viewModel.callSessionActive ? "Listening" : "Call Ready"
        }
    }

    private var callPhaseSubtitle: String {
        if viewModel.isWaitingForCallResponse {
            return "Waiting for Claude Code to respond"
        }

        if viewModel.queuedCallSpeechCount > 0 {
            return "\(viewModel.queuedCallSpeechCount) response\(viewModel.queuedCallSpeechCount == 1 ? "" : "s") ready to play"
        }

        switch viewModel.state {
        case .recording:
            return "Pause briefly or tap the green button to send."
        case .uploading:
            return "Sending text to Dropbox"
        case .paused:
            return "Call paused"
        case .idle:
            return viewModel.callSessionActive ? "Preparing the next turn" : ""
        }
    }

    private var callOrbLevel: CGFloat {
        guard viewModel.state == .recording else { return 0.08 }
        let recent = viewModel.waveformSamples.suffix(8)
        guard !recent.isEmpty else { return 0.08 }
        return recent.reduce(0, +) / CGFloat(recent.count)
    }

    private var callOrbColor: Color {
        if viewModel.isWaitingForCallResponse {
            return .blue
        }

        switch viewModel.state {
        case .recording:
            return .green
        case .uploading:
            return .orange
        case .paused:
            return .yellow
        case .idle:
            return viewModel.callSessionActive ? .green : .white
        }
    }

    private var callOrbSymbol: String {
        if viewModel.isWaitingForCallResponse {
            return "sparkles"
        }

        if canSendCallTurn {
            return "paperplane.fill"
        }

        switch viewModel.state {
        case .recording:
            return "waveform"
        case .uploading:
            return "arrow.up"
        case .paused:
            return "pause.fill"
        case .idle:
            return viewModel.callSessionActive ? "waveform" : "phone.fill"
        }
    }

    private var callPulseSpeed: Double {
        viewModel.isWaitingForCallResponse ? 3.0 : 5.5
    }

    private var callThinkingPulse: Double {
        viewModel.isWaitingForCallResponse ? 0.07 : 0.02
    }

    private var callOpacityPulse: Double {
        if viewModel.isWaitingForCallResponse {
            return 0.12
        }
        return viewModel.state == .recording ? 0.06 : 0.02
    }

    private var callOrbOpacity: Double {
        if viewModel.isWaitingForCallResponse {
            return 0.72
        }

        switch viewModel.state {
        case .recording:
            return 0.9
        case .uploading:
            return 0.8
        case .paused:
            return 0.62
        case .idle:
            return viewModel.callSessionActive ? 0.78 : 0.48
        }
    }

    private var callStatusColor: Color {
        if viewModel.isWaitingForCallResponse {
            return .blue
        }
        if viewModel.callSessionActive {
            return .green
        }
        return .white.opacity(0.58)
    }

    private var canCancelCallInteraction: Bool {
        viewModel.state == .recording
        || viewModel.state == .paused
        || viewModel.state == .uploading
        || viewModel.queuedCallSpeechCount > 0
    }

    private var canSendCallTurn: Bool {
        viewModel.callSessionActive && (viewModel.state == .recording || viewModel.state == .paused)
    }

    private var latestAssistantMessage: VoiceThreadMessage? {
        viewModel.threadMessages.last { $0.role == .assistant || $0.role == .status }
    }

    private func sendTypedMessage() {
        let message = typedMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty else { return }
        typedMessage = ""
        Task {
            await viewModel.sendTypedMessage(message)
        }
    }

    private func threadBubble(_ message: VoiceThreadMessage, compact: Bool) -> some View {
        HStack {
            if message.role == .user {
                Spacer(minLength: compact ? 22 : 46)
            }

            Text(message.text)
                .font(.system(size: compact ? 12 : 15, weight: .medium))
                .foregroundStyle(threadTextColor(for: message.role))
                .lineLimit(compact ? 3 : nil)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: compact ? .infinity : 280, alignment: .leading)
                .padding(.horizontal, compact ? 10 : 14)
                .padding(.vertical, compact ? 7 : 10)
                .background(threadBackground(for: message.role), in: RoundedRectangle(cornerRadius: compact ? 12 : 18, style: .continuous))

            if message.role != .user {
                Spacer(minLength: compact ? 22 : 46)
            }
        }
        .frame(maxWidth: .infinity, alignment: threadAlignment(for: message.role))
    }

    private var transportControls: some View {
        VStack(spacing: 14) {
            HStack(alignment: .center, spacing: 24) {
                transportSideButton(title: primaryButtonLabel) {
                    viewModel.togglePause()
                }
                .disabled(!(viewModel.state == .recording || viewModel.state == .paused))
                .opacity(viewModel.state == .recording || viewModel.state == .paused ? 1.0 : 0.0)
                .frame(maxWidth: .infinity, alignment: .center)

                recordButton
                    .frame(maxWidth: .infinity, alignment: .center)

                transportSideButton(title: "Cancel") {
                    viewModel.cancelRecording()
                }
                .disabled(viewModel.state == .idle)
                .opacity(viewModel.state == .idle ? 0.0 : 1.0)
                .frame(maxWidth: .infinity, alignment: .center)
            }

            pasteModeToggle
        }
    }

    private var recordButton: some View {
        Button {
            Task {
                await viewModel.toggleRecording()
            }
        } label: {
            Circle()
                .fill(viewModel.state == .recording ? .red : .white.opacity(0.1))
                .frame(width: 68, height: 68)
                .overlay(
                    Circle()
                        .stroke(.white.opacity(0.2), lineWidth: 3)
                )
                .overlay(
                    Group {
                        if viewModel.state == .recording {
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(.white.opacity(0.94))
                                .frame(width: 13, height: 13)
                        } else if viewModel.state == .uploading {
                            ProgressView()
                                .tint(.red)
                        } else {
                            Circle()
                                .fill(.red)
                                .frame(width: 40, height: 40)
                        }
                    }
                )
        }
        .accessibilityIdentifier("recordButton")
    }

    private var pasteModeToggle: some View {
        Button {
            viewModel.submitAfterPaste.toggle()
            viewModel.persistSubmitAfterPaste()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "arrow.turn.down.left")
                    .font(.system(size: 13, weight: .bold))
            }
            .foregroundStyle(viewModel.submitAfterPaste ? .black : .white.opacity(0.32))
            .frame(width: 48, height: 30)
            .background(
                Capsule()
                    .fill(viewModel.submitAfterPaste ? Color.white : Color.white.opacity(0.045))
            )
            .overlay(
                Capsule()
                    .stroke(Color.white.opacity(viewModel.submitAfterPaste ? 0.2 : 0.07), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var routeSelector: some View {
        Button {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                showRoutePicker = true
            }
        } label: {
            HStack(spacing: 6) {
                Text("Route")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.5))

                Text(viewModel.routeTarget.label)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white)

                Image(systemName: "chevron.up")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white.opacity(0.4))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(Color.white.opacity(0.08), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var favoriteRouteButtons: some View {
        let routes = viewModel.quickRouteTargets

        WrappingFavoriteRouteLayout(horizontalSpacing: 8, verticalSpacing: 8) {
            ForEach(routes) { route in
                favoriteRouteButton(route)
            }
        }
        .frame(maxWidth: 330)
        .animation(.spring(response: 0.24, dampingFraction: 0.86), value: routes.map(\.rawValue))
        .accessibilityIdentifier("favoriteRouteButtons")
    }

    private func favoriteRouteButton(_ route: RecordingViewModel.RouteTarget) -> some View {
        let isSelected = viewModel.routeTarget == route

        return Button {
            viewModel.routeTarget = route
            viewModel.persistRouteTarget()
        } label: {
            Text(route.label)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.82)
                .foregroundStyle(isSelected ? .black : .white.opacity(0.86))
                .padding(.horizontal, 16)
                .frame(minWidth: 86)
                .frame(height: 34)
                .background(
                    Capsule()
                        .fill(isSelected ? Color.white : Color.white.opacity(0.08))
                )
                .overlay(
                    Capsule()
                        .stroke(Color.white.opacity(isSelected ? 0.18 : 0.08), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Set route to \(route.label)")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private var voiceCallToggle: some View {
        Button {
            Task {
                await viewModel.toggleCallView()
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: viewModel.voiceCallModeEnabled || viewModel.callSessionActive ? "phone.fill" : "phone")
                    .font(.system(size: 12, weight: .bold))

                Text("Call")
                    .font(.system(size: 14, weight: .medium))
            }
            .foregroundStyle(viewModel.voiceCallModeEnabled || viewModel.callSessionActive ? .black : .white.opacity(0.82))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(viewModel.voiceCallModeEnabled || viewModel.callSessionActive ? Color.green : Color.white.opacity(0.08))
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("voiceCallToggle")
    }

    private var textResponseToggle: some View {
        Button {
            viewModel.toggleTextResponseMode()
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "text.bubble.fill")
                    .font(.system(size: 11, weight: .bold))

                Text("Text")
                    .font(.system(size: 13, weight: .medium))
            }
            .foregroundStyle(viewModel.textResponseModeEnabled ? .black : .white.opacity(0.78))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(viewModel.textResponseModeEnabled ? Color.white : Color.white.opacity(0.08))
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("textResponseToggle")
    }

    private var routePickerColumns: [GridItem] {
        [
            GridItem(.flexible(minimum: 96, maximum: 150), spacing: 8),
            GridItem(.flexible(minimum: 96, maximum: 150), spacing: 8)
        ]
    }

    private func routePill(
        _ route: RecordingViewModel.RouteTarget,
        collapseOnSelect: Bool,
        emphasizeSelected: Bool = true
    ) -> some View {
        Text(route.label)
            .font(.system(size: 13, weight: .medium))
            .lineLimit(1)
            .minimumScaleFactor(0.82)
            .foregroundStyle(
                emphasizeSelected && viewModel.routeTarget == route ? .black : .white
            )
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .frame(minHeight: 34)
            .background(
                Capsule()
                    .fill(
                        emphasizeSelected && viewModel.routeTarget == route
                        ? .white
                        : .white.opacity(0.1)
                    )
            )
            .contentShape(Capsule())
            .onTapGesture {
                viewModel.routeTarget = route
                viewModel.persistRouteTarget()
                if collapseOnSelect {
                    withAnimation(.spring(response: 0.24, dampingFraction: 0.86)) {
                        showRoutePicker = false
                    }
                }
            }
            .accessibilityAddTraits(.isButton)
            .accessibilityHint("Tap to select.")
    }

    private var routePickerOverlay: some View {
        GeometryReader { geometry in
            let pickerY = min(geometry.size.height - 178, geometry.size.height * 0.68)

            ZStack {
                Color.black.opacity(0.001)
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation(.spring(response: 0.24, dampingFraction: 0.86)) {
                        showRoutePicker = false
                    }
                }

                VStack(spacing: 10) {
                    LazyVGrid(columns: routePickerColumns, spacing: 12) {
                        ForEach(RecordingViewModel.RouteTarget.allCases) { route in
                            routePill(route, collapseOnSelect: true, emphasizeSelected: false)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 14)
                }
                .frame(width: min(geometry.size.width - 44, 330))
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.45), radius: 22, y: 10)
                .position(x: geometry.size.width / 2, y: pickerY)
            }
        }
        .transition(.scale(scale: 0.94).combined(with: .opacity))
        .zIndex(10)
    }

    private func transportSideButton(title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 66)
        }
        .buttonStyle(.plain)
    }

    private var waveform: some View {
        HStack(spacing: 3) {
            ForEach(0..<viewModel.waveformSamples.count, id: \.self) { index in
                RoundedRectangle(cornerRadius: 2)
                    .fill(waveColor(for: index))
                    .frame(width: 3, height: waveHeight(for: viewModel.waveformSamples[index]))
            }
        }
        .frame(height: 64)
        .frame(maxWidth: .infinity)
    }

    private var primaryButtonLabel: String {
        switch viewModel.state {
        case .idle: return "Pause"
        case .recording: return "Pause"
        case .paused: return "Resume"
        case .uploading: return "..."
        }
    }

    private var statusLine: String {
        switch viewModel.state {
        case .idle:
            if viewModel.pendingBackgroundUploadCount > 0 {
                return viewModel.pendingBackgroundUploadCount == 1
                    ? "Ready - uploading previous"
                    : "Ready - uploading \(viewModel.pendingBackgroundUploadCount)"
            }
            if let error = viewModel.lastBackgroundUploadError {
                return "Upload failed: \(error)"
            }
            return "Ready"
        case .recording: return "Recording..."
        case .paused: return "Paused"
        case .uploading: return dropboxManager.isReadyForUpload ? "Uploading to Dropbox" : "Uploading to Mac"
        }
    }

    private var statusColor: Color {
        switch viewModel.state {
        case .idle:
            if viewModel.lastBackgroundUploadError != nil {
                return .red
            }
            if viewModel.pendingBackgroundUploadCount > 0 {
                return .blue
            }
            return .white.opacity(0.4)
        case .recording: return .red
        case .paused: return .yellow
        case .uploading: return .blue
        }
    }

    private func formattedTime(_ interval: TimeInterval) -> String {
        let minutes = Int(interval) / 60
        let seconds = Int(interval) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    private func waveHeight(for sample: CGFloat) -> CGFloat {
        let minHeight: CGFloat = 4
        let maxHeight: CGFloat = 46
        // Sample is 0-1.0
        return minHeight + (sample * (maxHeight - minHeight))
    }

    private func waveColor(for index: Int) -> Color {
        if viewModel.state == .recording {
            return .red.opacity(0.8)
        } else if viewModel.state == .uploading {
            return .orange.opacity(0.85)
        }
        return .white.opacity(0.2)
    }

    private func threadAlignment(for role: VoiceThreadMessage.Role) -> Alignment {
        switch role {
        case .user: return .trailing
        case .assistant, .status: return .leading
        }
    }

    private func threadTextColor(for role: VoiceThreadMessage.Role) -> Color {
        switch role {
        case .user: return .black.opacity(0.82)
        case .assistant: return .white.opacity(0.88)
        case .status: return .white.opacity(0.46)
        }
    }

    private func threadBackground(for role: VoiceThreadMessage.Role) -> Color {
        switch role {
        case .user: return .white.opacity(0.82)
        case .assistant: return .white.opacity(0.11)
        case .status: return .clear
        }
    }

    private static func launchAdjustment(named key: String) -> CGFloat {
        guard let rawValue = ProcessInfo.processInfo.environment[key],
              let value = Double(rawValue) else {
            return 0
        }
        return CGFloat(value)
    }
}

private struct WrappingFavoriteRouteLayout: Layout {
    let horizontalSpacing: CGFloat
    let verticalSpacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = resolvedWidth(for: proposal, subviews: subviews)
        return arrangement(in: maxWidth, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let arrangement = arrangement(in: bounds.width, subviews: subviews)

        for item in arrangement.items {
            subviews[item.index].place(
                at: CGPoint(x: bounds.minX + item.origin.x, y: bounds.minY + item.origin.y),
                proposal: ProposedViewSize(item.size)
            )
        }
    }

    private func resolvedWidth(for proposal: ProposedViewSize, subviews: Subviews) -> CGFloat {
        if let width = proposal.width {
            return width
        }

        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let contentWidth = sizes.reduce(CGFloat.zero) { $0 + $1.width }
        let spacingWidth = horizontalSpacing * CGFloat(max(0, sizes.count - 1))
        return contentWidth + spacingWidth
    }

    private func arrangement(in maxWidth: CGFloat, subviews: Subviews) -> (size: CGSize, items: [LayoutItem]) {
        guard maxWidth > 0, !subviews.isEmpty else {
            return (.zero, [])
        }

        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        var rows: [LayoutRow] = []
        var currentRow = LayoutRow()

        for index in sizes.indices {
            let size = sizes[index]
            let proposedWidth = currentRow.items.isEmpty
                ? size.width
                : currentRow.width + horizontalSpacing + size.width

            if proposedWidth > maxWidth, !currentRow.items.isEmpty {
                rows.append(currentRow)
                currentRow = LayoutRow()
            }

            currentRow.append(index: index, size: size, spacing: horizontalSpacing)
        }

        if !currentRow.items.isEmpty {
            rows.append(currentRow)
        }

        var positionedItems: [LayoutItem] = []
        var y: CGFloat = 0

        for row in rows {
            var x = max(0, (maxWidth - row.width) / 2)

            for item in row.items {
                let origin = CGPoint(x: x, y: y + ((row.height - item.size.height) / 2))
                positionedItems.append(LayoutItem(index: item.index, size: item.size, origin: origin))
                x += item.size.width + horizontalSpacing
            }

            y += row.height + verticalSpacing
        }

        return (
            CGSize(width: maxWidth, height: max(0, y - verticalSpacing)),
            positionedItems
        )
    }

    private struct LayoutItem {
        let index: Int
        let size: CGSize
        var origin: CGPoint = .zero
    }

    private struct LayoutRow {
        var items: [LayoutItem] = []
        var width: CGFloat = 0
        var height: CGFloat = 0

        mutating func append(index: Int, size: CGSize, spacing: CGFloat) {
            if !items.isEmpty {
                width += spacing
            }

            items.append(LayoutItem(index: index, size: size))
            width += size.width
            height = max(height, size.height)
        }
    }
}
