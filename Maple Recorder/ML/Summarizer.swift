#if !os(watchOS)
import Foundation

struct SummaryResult: Sendable {
    var title: String
    var tags: [String]
    var summary: String
}

enum Summarizer {
    private static let systemPrompt = """
        You are a concise meeting summarizer. Given a transcript of a recording, produce:\
        \n\nLine 1: A short descriptive title (3-7 words, no quotes, no prefix).\
        \nLine 2: 3-5 comma-separated single-word uppercase tags categorizing the recording (e.g. MEETING, DESIGN, PLANNING, STANDUP, INTERVIEW).\
        \nLine 3+: A brief summary paragraph (2-4 sentences) capturing the key topics discussed, \
        decisions made, and any action items. Do not use bullet points or headers — \
        write a flowing paragraph. Be specific about who said what when relevant.
        """

    private static let chunkSummaryPrompt = """
        You are a concise meeting summarizer. Given a portion of a transcript, write a brief \
        summary paragraph (2-4 sentences) capturing the key topics discussed, decisions made, \
        and any action items. Be specific about who said what when relevant. \
        Output only the summary paragraph, nothing else.
        """

    private static let combinePrompt = """
        You are a concise meeting summarizer. You are given multiple partial summaries from \
        different sections of the same recording. Combine them into a single cohesive result:\
        \n\nLine 1: A short descriptive title (3-7 words, no quotes, no prefix).\
        \nLine 2: 3-5 comma-separated single-word uppercase tags categorizing the recording (e.g. MEETING, DESIGN, PLANNING, STANDUP, INTERVIEW).\
        \nLine 3+: A brief summary paragraph (2-4 sentences) capturing the key topics discussed, \
        decisions made, and any action items. Do not use bullet points or headers — \
        write a flowing paragraph. Be specific about who said what when relevant.
        """

    /// Maximum character count per chunk. Apple Foundation Models has a limited context,
    /// so we keep chunks conservative. Cloud providers could handle more but we use
    /// the same limit for consistency.
    private static let maxChunkCharacters = 12_000

    static func summarize(
        transcript: [TranscriptSegment],
        speakers: [Speaker],
        provider: LLMProvider
    ) async throws -> SummaryResult {
        guard let service = LLMServiceFactory.service(for: provider) else {
            return SummaryResult(title: "", tags: [], summary: "")
        }
        guard service.isAvailable else { return SummaryResult(title: "", tags: [], summary: "") }

        let transcriptText = formatTranscript(transcript, speakers: speakers)
        guard !transcriptText.isEmpty else { return SummaryResult(title: "", tags: [], summary: "") }

        // If the transcript fits in a single chunk, summarize directly
        if transcriptText.count <= maxChunkCharacters {
            let response = try await service.generate(
                systemPrompt: systemPrompt,
                userMessage: transcriptText
            )
            return parseResponse(response)
        }

        // Chunk the transcript and summarize each chunk, then combine
        return try await chunkedSummarize(
            transcript: transcript,
            speakers: speakers,
            service: service
        )
    }

    // MARK: - Chunked Summarization

    private static func chunkedSummarize(
        transcript: [TranscriptSegment],
        speakers: [Speaker],
        service: any LLMService
    ) async throws -> SummaryResult {
        let chunks = splitIntoChunks(transcript, speakers: speakers)

        // Summarize each chunk
        var chunkSummaries: [String] = []
        for chunk in chunks {
            let chunkText = formatTranscript(chunk, speakers: speakers)
            let summary = try await service.generate(
                systemPrompt: chunkSummaryPrompt,
                userMessage: chunkText
            )
            let trimmed = summary.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                chunkSummaries.append(trimmed)
            }
        }

        guard !chunkSummaries.isEmpty else {
            return SummaryResult(title: "", tags: [], summary: "")
        }

        // If only one chunk produced a summary, still run through the final prompt
        // to get the title/tags format
        let combinedInput = chunkSummaries.enumerated().map { index, summary in
            "Part \(index + 1):\n\(summary)"
        }.joined(separator: "\n\n")

        let finalResponse = try await service.generate(
            systemPrompt: combinePrompt,
            userMessage: combinedInput
        )

        return parseResponse(finalResponse)
    }

    private static func splitIntoChunks(
        _ segments: [TranscriptSegment],
        speakers: [Speaker]
    ) -> [[TranscriptSegment]] {
        var chunks: [[TranscriptSegment]] = []
        var currentChunk: [TranscriptSegment] = []
        var currentLength = 0

        for segment in segments {
            let name = speakers.first { $0.id == segment.speakerId }?.displayName ?? segment.speakerId
            let segmentLength = name.count + 2 + segment.text.count + 1 // "name: text\n"

            if currentLength + segmentLength > maxChunkCharacters && !currentChunk.isEmpty {
                chunks.append(currentChunk)
                currentChunk = []
                currentLength = 0
            }

            currentChunk.append(segment)
            currentLength += segmentLength
        }

        if !currentChunk.isEmpty {
            chunks.append(currentChunk)
        }

        return chunks
    }

    // MARK: - Parsing

    private static func parseResponse(_ response: String) -> SummaryResult {
        let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)
        let lines = trimmed.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        guard lines.count >= 3 else {
            // Less than 3 lines — treat entire response as summary, no tags
            return SummaryResult(title: lines.first ?? "", tags: [], summary: trimmed)
        }

        let title = lines[0]
        let tags = lines[1]
            .components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespaces).uppercased() }
            .filter { !$0.isEmpty }
        let summary = lines.dropFirst(2).joined(separator: " ")
        return SummaryResult(title: title, tags: tags, summary: summary)
    }

    private static func formatTranscript(
        _ segments: [TranscriptSegment],
        speakers: [Speaker]
    ) -> String {
        segments.map { segment in
            let name = speakers.first { $0.id == segment.speakerId }?.displayName ?? segment.speakerId
            return "\(name): \(segment.text)"
        }.joined(separator: "\n")
    }
}
#endif
