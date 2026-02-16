#if !os(watchOS)
import Foundation
import Observation

@Observable
final class ModelManager {
    var isReady = false
    var isDownloading = false
    var error: String?

    let transcriptionManager = TranscriptionManager()
    let diarizationManager = DiarizationManager()

    func ensureModelsReady() async {
        guard !isReady else { return }
        isDownloading = true
        error = nil

        do {
            async let asrInit: () = transcriptionManager.initialize()
            async let diaInit: () = diarizationManager.initialize()
            _ = try await (asrInit, diaInit)
            isReady = true
        } catch {
            self.error = error.localizedDescription
        }

        isDownloading = false
    }

    func createPipeline() -> ProcessingPipeline {
        ProcessingPipeline()
    }
}
#endif
