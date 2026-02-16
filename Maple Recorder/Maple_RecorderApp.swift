import SwiftUI

@main
struct Maple_RecorderApp: App {
    @State private var store = RecordingStore()
    #if !os(watchOS)
    @State private var modelManager = ModelManager()
    @State private var settingsManager = SettingsManager()
    @State private var promptStore = PromptStore()
    #endif
    #if os(iOS)
    @State private var phoneTransferHandler = PhoneTransferHandler()
    #endif

    var body: some Scene {
        WindowGroup {
            #if os(watchOS)
            WatchRecordingView(store: store)
            #else
            RecordingListView(
                store: store,
                modelManager: modelManager,
                settingsManager: settingsManager,
                promptStore: promptStore
            )
            .task {
                await modelManager.ensureModelsReady()
            }
            #if os(iOS)
            .onAppear {
                phoneTransferHandler.configure(
                    store: store,
                    modelManager: modelManager,
                    settingsManager: settingsManager
                )
            }
            #endif
            #endif
        }
    }
}
