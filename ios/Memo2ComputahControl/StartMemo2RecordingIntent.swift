import AppIntents

@available(iOS 18.0, *)
struct StartMemo2RecordingIntent: AppIntent {
    static var title: LocalizedStringResource = "Start Memo2 Recording"
    static var description = IntentDescription("Open Memo2 and begin recording immediately.")
    static var openAppWhenRun = true

    @Dependency private var launchCoordinator: RecordingLaunchCoordinator

    @MainActor
    func perform() async throws -> some IntentResult {
        launchCoordinator.requestAutoStart()
        return .result()
    }
}
