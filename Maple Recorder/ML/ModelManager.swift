#if !os(watchOS)
import Foundation
import Observation

enum ModelDownloadStep: String, Sendable {
    case idle = ""
    case downloadingASR = "Downloading speech model…"
    case downloadingDiarization = "Downloading speaker model…"
    case loadingASR = "Loading speech model…"
    case loadingDiarization = "Loading speaker model…"
    case compilingModels = "Compiling models…"
    case ready = "Models ready"
    case failed = "Download failed"
}

@Observable
final class ModelManager {
    var isReady = false
    var isDownloading = false
    var downloadStep: ModelDownloadStep = .idle
    var downloadProgress: Double = 0 // 0.0 to 1.0
    var error: String?

    let transcriptionManager = TranscriptionManager()
    let diarizationManager = DiarizationManager()

    func ensureModelsReady() async {
        guard !isReady else { return }
        isDownloading = true
        error = nil
        downloadProgress = 0

        let asrCached = transcriptionManager.isModelReady
        let diarCached = diarizationManager.isModelReady

        do {
            // Step 1: ASR model (~60% of total)
            downloadStep = asrCached ? .loadingASR : .downloadingASR
            downloadProgress = 0.05
            try await transcriptionManager.initialize()
            downloadProgress = 0.55

            // Step 2: Diarization model (~35% of total)
            downloadStep = diarCached ? .loadingDiarization : .downloadingDiarization
            downloadProgress = 0.6
            try await diarizationManager.initialize()
            downloadProgress = 0.95

            // Step 3: Done
            downloadStep = .ready
            downloadProgress = 1.0
            isReady = true
        } catch {
            downloadStep = .failed
            self.error = error.localizedDescription
        }

        isDownloading = false
    }

    func createPipeline() -> ProcessingPipeline {
        ProcessingPipeline()
    }
}
#endif
