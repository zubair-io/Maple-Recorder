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
        systemAudioURLs: [URL] = [],
        transcriptionManager: TranscriptionManager,
        diarizationManager: DiarizationManager,
        summarizationProvider: LLMProvider = .none
    ) async throws -> (segments: [TranscriptSegment], speakers: [Speaker], summary: String, generatedTitle: String, tags: [String]) {
        do {
            state = .converting
            progress = "Converting audio…"
            let micSamples: [Float]
            if audioURLs.count == 1 {
                micSamples = try MapleAudioConverter.loadAndResample(url: audioURLs[0])
            } else {
                micSamples = try MapleAudioConverter.loadAndResampleChunks(urls: audioURLs)
            }

            // Load system audio samples if present
            let systemSamples: [Float]
            if !systemAudioURLs.isEmpty {
                systemSamples = try MapleAudioConverter.loadAndResampleChunks(urls: systemAudioURLs)
            } else {
                systemSamples = []
            }

            state = .transcribing
            progress = "Transcribing…"

            let asrSegments: [RawASRSegment]
            let diaSegments: [RawDiarizationSegment]

            if systemSamples.isEmpty {
                // Mic-only path — same as before
                async let asrResult = transcriptionManager.transcribe(micSamples)
                async let diaResult = diarizationManager.diarize(micSamples)

                let (asr, dia) = try await (asrResult, diaResult)
                asrSegments = mapASRResult(asr)
                diaSegments = mapDiarizationResult(dia)
            } else {
                // Two-track path: mix for ASR, diarize each track independently
                let combinedSamples = MapleAudioConverter.mixSamples(micSamples, systemSamples)

                async let asrResult = transcriptionManager.transcribe(combinedSamples)
                async let micDiaResult = diarizationManager.diarize(micSamples)
                async let sysDiaResult = diarizationManager.diarize(systemSamples)

                let (asr, micDia, sysDia) = try await (asrResult, micDiaResult, sysDiaResult)

                asrSegments = mapASRResult(asr)

                // Namespace speaker IDs so mic and system speakers never merge
                let micDiaSegments = mapDiarizationResult(micDia).map { seg in
                    RawDiarizationSegment(speakerId: "mic_\(seg.speakerId)", start: seg.start, end: seg.end)
                }
                let sysDiaSegments = mapDiarizationResult(sysDia).map { seg in
                    RawDiarizationSegment(speakerId: "sys_\(seg.speakerId)", start: seg.start, end: seg.end)
                }
                diaSegments = micDiaSegments + sysDiaSegments
            }

            state = .merging
            progress = "Aligning transcript…"

            let merged = TranscriptMerger.merge(asrSegments: asrSegments, diarizationSegments: diaSegments)

            // Summarize and generate title if provider is configured
            var summary = ""
            var generatedTitle = ""
            var tags: [String] = []
            if summarizationProvider != .none {
                state = .summarizing
                progress = "Generating summary…"
                let result = (try? await Summarizer.summarize(
                    transcript: merged.segments,
                    speakers: merged.speakers,
                    provider: summarizationProvider
                )) ?? SummaryResult(title: "", tags: [], summary: "")
                generatedTitle = result.title
                tags = result.tags
                summary = result.summary
            }

            state = .complete
            progress = ""
            return (segments: merged.segments, speakers: merged.speakers, summary: summary, generatedTitle: generatedTitle, tags: tags)
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
                let text = currentTokens.map(\.token).joined()
                    .replacingOccurrences(of: "  ", with: " ")
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
