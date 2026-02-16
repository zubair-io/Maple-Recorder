import SwiftUI

@main
struct Maple_RecorderApp: App {
    @State private var store = RecordingStore()

    var body: some Scene {
        WindowGroup {
            RecordingListView(store: store)
        }
    }
}
