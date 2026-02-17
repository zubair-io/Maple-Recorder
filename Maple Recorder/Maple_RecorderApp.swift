import SwiftUI

@main
struct Maple_RecorderApp: App {
    @State private var store = RecordingStore()
    @State private var syncMonitor: ICloudSyncMonitor?
    #if !os(watchOS)
    @State private var modelManager = ModelManager()
    @State private var settingsManager = SettingsManager()
    @State private var promptStore = PromptStore()
    @State private var autoProcessor: AutoProcessor?
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
                .onAppear {
                    let monitor = ICloudSyncMonitor(store: store)
                    monitor.startMonitoring()
                    syncMonitor = monitor
                }
            #else
            RecordingListView(
                store: store,
                modelManager: modelManager,
                settingsManager: settingsManager,
                promptStore: promptStore,
                autoProcessor: autoProcessor
            )
            .task {
                let monitor = ICloudSyncMonitor(store: store)
                monitor.startMonitoring()
                syncMonitor = monitor

                await modelManager.ensureModelsReady()

                let processor = AutoProcessor(store: store, modelManager: modelManager, settingsManager: settingsManager)
                autoProcessor = processor
                processor.startWatching()
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
                quickRecordController.registerGlobalHotkey()
                quickRecordController.requestNotificationPermission()
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
                .keyboardShortcut(".", modifiers: [.control])

                Button("Quick Record with System Audio") {
                    quickRecordController.toggleWithSystemAudio()
                }
                .keyboardShortcut("/", modifiers: [.control])
            }
        }
        #endif
    }
}
