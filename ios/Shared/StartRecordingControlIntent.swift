import AppIntents

@available(iOS 18.0, *)
struct StartRecordingControlIntent: AppIntent {
    static var title: LocalizedStringResource = "Start Recording"
    static var description = IntentDescription("Open Mobile Recorder and begin recording immediately.")
    static var openAppWhenRun = true

    @Dependency private var launchCoordinator: RecordingLaunchCoordinator

    @MainActor
    func perform() async throws -> some IntentResult {
        launchCoordinator.requestAutoStart()
        return .result()
    }
}
