#if !os(watchOS)
import Foundation

enum Summarizer {
    private static let systemPrompt = """
        You are a concise meeting summarizer. Given a transcript of a recording, \
        produce a brief summary paragraph (2-4 sentences) capturing the key topics discussed, \
        decisions made, and any action items. Do not use bullet points or headers — \
        write a flowing paragraph. Be specific about who said what when relevant.
        """

    static func summarize(
        transcript: [TranscriptSegment],
        speakers: [Speaker],
        provider: LLMProvider
    ) async throws -> String {
        guard let service = LLMServiceFactory.service(for: provider) else {
            return ""
        }
        guard service.isAvailable else { return "" }

        let transcriptText = formatTranscript(transcript, speakers: speakers)
        guard !transcriptText.isEmpty else { return "" }

        return try await service.generate(
            systemPrompt: systemPrompt,
            userMessage: transcriptText
        )
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
