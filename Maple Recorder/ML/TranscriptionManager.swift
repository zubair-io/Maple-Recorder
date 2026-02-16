#if !os(watchOS)
import FluidAudio
import Foundation
import Observation

enum TranscriptionError: Error, Sendable {
    case notInitialized
}

@Observable
final class TranscriptionManager {
    var isModelReady = false
    var isTranscribing = false

    private var asrManager: AsrManager?

    func initialize() async throws {
        let models = try await AsrModels.downloadAndLoad(version: .v3)
        let manager = AsrManager(config: .default)
        try await manager.initialize(models: models)
        self.asrManager = manager
        self.isModelReady = true
    }

    func transcribe(_ samples: [Float]) async throws -> ASRResult {
        isTranscribing = true
        defer { isTranscribing = false }
        guard let manager = asrManager else { throw TranscriptionError.notInitialized }
        return try await manager.transcribe(samples)
    }
}
#endif
