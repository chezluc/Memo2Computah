import SwiftUI
import WidgetKit

struct MobileRecorderControlWidget: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.garnetuniverse.MobileRecorder.StartRecording") {
            ControlWidgetButton(action: StartRecordingControlIntent()) {
                Label("Start Recording", systemImage: "record.circle.fill")
            }
        }
        .displayName("Start Recording")
        .description("Open Mobile Recorder and begin recording immediately.")
    }
}
