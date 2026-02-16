import SwiftUI

@main
struct Maple_RecorderApp: App {
    @State private var store = RecordingStore()
    #if !os(watchOS)
    @State private var modelManager = ModelManager()
    #endif

    var body: some Scene {
        WindowGroup {
            #if !os(watchOS)
            RecordingListView(store: store, modelManager: modelManager)
                .task {
                    await modelManager.ensureModelsReady()
                }
            #else
            RecordingListView(store: store)
            #endif
        }
    }
}
