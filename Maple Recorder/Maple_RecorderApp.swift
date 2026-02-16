import SwiftUI

@main
struct Maple_RecorderApp: App {
    @State private var store = RecordingStore()
    #if !os(watchOS)
    @State private var modelManager = ModelManager()
    @State private var settingsManager = SettingsManager()
    @State private var promptStore = PromptStore()
    #endif

    var body: some Scene {
        WindowGroup {
            #if !os(watchOS)
            RecordingListView(
                store: store,
                modelManager: modelManager,
                settingsManager: settingsManager,
                promptStore: promptStore
            )
            .task {
                await modelManager.ensureModelsReady()
            }
            #else
            RecordingListView(store: store)
            #endif
        }
    }
}
