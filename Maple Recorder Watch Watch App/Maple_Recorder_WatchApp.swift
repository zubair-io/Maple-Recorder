import SwiftUI

@main
struct Maple_Recorder_WatchApp: App {
    @State private var store = RecordingStore()
    @State private var syncMonitor: ICloudSyncMonitor?

    var body: some Scene {
        WindowGroup {
            WatchRecordingView(store: store)
                .onAppear {
                    let monitor = ICloudSyncMonitor(store: store)
                    monitor.startMonitoring()
                    syncMonitor = monitor
                }
        }
    }
}
