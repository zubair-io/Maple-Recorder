import SwiftUI

@main
struct Maple_Recorder_WatchApp: App {
    @State private var store = RecordingStore()

    var body: some Scene {
        WindowGroup {
            WatchRecordingView(store: store)
        }
    }
}
