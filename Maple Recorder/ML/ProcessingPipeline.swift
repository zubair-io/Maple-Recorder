#if !os(watchOS)
import FluidAudio
import Foundation
import Observation

enum ProcessingState: Sendable {
    case idle
    case converting
    case transcribing
    case merging
    case complete
    case failed(String)
}

@Observable
final class ProcessingPipeline {
    var state: ProcessingState = .idle
    var progress: String = ""

    func process(
        audioURL: URL,
        transcriptionManager: TranscriptionManager,
        diarizationManager: DiarizationManager
    ) async throws -> (segments: [TranscriptSegment], speakers: [Speaker]) {
        do {
            state = .converting
            progress = "Converting audio…"
            let samples = try MapleAudioConverter.loadAndResample(url: audioURL)

            state = .transcribing
            progress = "Transcribing…"

            async let asrResult = transcriptionManager.transcribe(samples)
            async let diaResult = diarizationManager.diarize(samples)

            let (asr, dia) = try await (asrResult, diaResult)

            state = .merging
            progress = "Aligning transcript…"

            let asrSegments = mapASRResult(asr)
            let diaSegments = mapDiarizationResult(dia)
            let merged = TranscriptMerger.merge(asrSegments: asrSegments, diarizationSegments: diaSegments)

            state = .complete
            progress = ""
            return merged
        } catch {
            state = .failed(error.localizedDescription)
            progress = ""
            throw error
        }
    }

    // MARK: - FluidAudio Result Mapping

    private func mapASRResult(_ result: ASRResult) -> [RawASRSegment] {
        // ASRResult provides tokenTimings for word-level timing.
        // Group tokens into sentence-like segments by punctuation or fixed chunks.
        guard let timings = result.tokenTimings, !timings.isEmpty else {
            // Fallback: single segment from full text with duration
            guard !result.text.isEmpty else { return [] }
            return [RawASRSegment(text: result.text, start: 0, end: result.duration)]
        }

        // Group tokens into segments split at sentence-ending punctuation
        var segments: [RawASRSegment] = []
        var currentTokens: [TokenTiming] = []

        for token in timings {
            currentTokens.append(token)
            let trimmed = token.token.trimmingCharacters(in: .whitespaces)
            let isSentenceEnd = trimmed.hasSuffix(".") || trimmed.hasSuffix("?")
                || trimmed.hasSuffix("!")

            if isSentenceEnd && !currentTokens.isEmpty {
                let text = currentTokens.map(\.token).joined(separator: " ")
                    .trimmingCharacters(in: .whitespaces)
                let start = currentTokens.first!.startTime
                let end = currentTokens.last!.endTime
                segments.append(RawASRSegment(text: text, start: start, end: end))
                currentTokens = []
            }
        }

        // Remaining tokens form a final segment
        if !currentTokens.isEmpty {
            let text = currentTokens.map(\.token).joined(separator: " ")
                .trimmingCharacters(in: .whitespaces)
            let start = currentTokens.first!.startTime
            let end = currentTokens.last!.endTime
            segments.append(RawASRSegment(text: text, start: start, end: end))
        }

        return segments
    }

    private func mapDiarizationResult(_ result: DiarizationResult) -> [RawDiarizationSegment] {
        result.segments.map { segment in
            RawDiarizationSegment(
                speakerId: segment.speakerId,
                start: TimeInterval(segment.startTimeSeconds),
                end: TimeInterval(segment.endTimeSeconds)
            )
        }
    }
}
#endif
