import SwiftUI
import WidgetKit

struct Memo2ComputahControlWidget: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.garnetuniverse.Memo2Computah.StartRecording") {
            ControlWidgetButton(action: StartMemo2RecordingIntent()) {
                Label("Start Memo2", systemImage: "desktopcomputer")
            }
        }
        .displayName("Start Memo2 Recording")
        .description("Open Memo2 and begin recording immediately.")
    }
}
