#if os(iOS)
import Foundation
import Observation
import WatchConnectivity

/// iOS-side handler: receives audio files from the paired Apple Watch
/// and triggers the full processing pipeline.
@Observable
final class PhoneTransferHandler: NSObject, WCSessionDelegate, @unchecked Sendable {
    var pendingTransfers: [URL] = []

    private var store: RecordingStore?
    private var modelManager: ModelManager?
    private var settingsManager: SettingsManager?

    func configure(store: RecordingStore, modelManager: ModelManager, settingsManager: SettingsManager) {
        self.store = store
        self.modelManager = modelManager
        self.settingsManager = settingsManager

        if WCSession.isSupported() {
            let session = WCSession.default
            session.delegate = self
            session.activate()
        }
    }

    // MARK: - WCSessionDelegate

    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {}

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    nonisolated func session(_ session: WCSession, didReceive file: WCSessionFile) {
        let metadata = file.metadata ?? [:]
        let tempURL = file.fileURL

        Task { @MainActor [weak self] in
            guard let self else { return }
            await self.handleReceivedFile(tempURL: tempURL, metadata: metadata)
        }
    }

    // MARK: - Private

    private func handleReceivedFile(tempURL: URL, metadata: [String: Any]) async {
        guard let store, let modelManager else { return }

        // Copy file to recordings directory
        let fileName = tempURL.lastPathComponent
        let destURL = StorageLocation.recordingsURL.appendingPathComponent(fileName)
        try? FileManager.default.copyItem(at: tempURL, to: destURL)

        let now = Date()
        let title = (metadata["title"] as? String) ?? "Watch Recording \(now.formatted(date: .abbreviated, time: .shortened))"

        let recording = MapleRecording(
            title: title,
            audioFiles: [fileName],
            createdAt: now,
            modifiedAt: now
        )

        do {
            try store.save(recording)
        } catch {
            print("Failed to save watch recording: \(error)")
            return
        }

        // Ensure models are downloaded before processing
        if !modelManager.isReady {
            await modelManager.ensureModelsReady()
        }
        guard modelManager.isReady else { return }

        let pipeline = modelManager.createPipeline()
        let provider = settingsManager?.preferredProvider ?? .none
        do {
            try await store.processRecording(
                recording,
                pipeline: pipeline,
                transcription: modelManager.transcriptionManager,
                diarization: modelManager.diarizationManager,
                summarizationProvider: provider
            )
        } catch {
            print("Watch recording processing failed: \(error)")
        }
    }
}
#endif
