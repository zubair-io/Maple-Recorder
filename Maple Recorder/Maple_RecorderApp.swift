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
    @State private var miniRecordingController = MiniRecordingController()
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
            #elseif os(macOS)
            RecordingListView(
                store: store,
                modelManager: modelManager,
                settingsManager: settingsManager,
                promptStore: promptStore,
                autoProcessor: autoProcessor,
                miniRecordingController: miniRecordingController
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
            .onAppear {
                quickRecordController.store = store
                quickRecordController.modelManager = modelManager
                quickRecordController.settingsManager = settingsManager
                quickRecordController.registerGlobalHotkey()
                quickRecordController.requestNotificationPermission()
                miniRecordingController.startMonitoring()
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
            .onAppear {
                phoneTransferHandler.configure(
                    store: store,
                    modelManager: modelManager,
                    settingsManager: settingsManager
                )
            }
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
