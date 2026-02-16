#if !os(watchOS)
import FluidAudio
import Foundation
import Observation

enum ProcessingState: Sendable {
    case idle
    case converting
    case transcribing
    case merging
    case summarizing
    case complete
    case failed(String)
}

@Observable
final class ProcessingPipeline {
    var state: ProcessingState = .idle
    var progress: String = ""

    func process(
        audioURLs: [URL],
        transcriptionManager: TranscriptionManager,
        diarizationManager: DiarizationManager,
        summarizationProvider: LLMProvider = .none
    ) async throws -> (segments: [TranscriptSegment], speakers: [Speaker], summary: String) {
        do {
            state = .converting
            progress = "Converting audio…"
            let samples: [Float]
            if audioURLs.count == 1 {
                samples = try MapleAudioConverter.loadAndResample(url: audioURLs[0])
            } else {
                samples = try MapleAudioConverter.loadAndResampleChunks(urls: audioURLs)
            }

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

            // Summarize if provider is configured
            var summary = ""
            if summarizationProvider != .none {
                state = .summarizing
                progress = "Generating summary…"
                summary = (try? await Summarizer.summarize(
                    transcript: merged.segments,
                    speakers: merged.speakers,
                    provider: summarizationProvider
                )) ?? ""
            }

            state = .complete
            progress = ""
            return (segments: merged.segments, speakers: merged.speakers, summary: summary)
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
