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
    #if os(macOS)
    @State private var quickRecordController = QuickRecordController()
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
            #if os(macOS)
            .onAppear {
                quickRecordController.store = store
                quickRecordController.modelManager = modelManager
                quickRecordController.settingsManager = settingsManager
            }
            #endif
            #endif
        }
        #if os(macOS)
        .commands {
            CommandGroup(after: .newItem) {
                Button("Quick Record") {
                    quickRecordController.toggle()
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])
            }
        }
        #endif
    }
}
