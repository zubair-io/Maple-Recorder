#if !os(watchOS)
import Foundation

enum PromptRunner {
    static func execute(
        prompt: CustomPrompt,
        additionalContext: String?,
        transcript: [TranscriptSegment],
        speakers: [Speaker],
        provider: LLMProvider
    ) async throws -> PromptResult {
        guard let service = LLMServiceFactory.service(for: provider) else {
            throw LLMServiceError.notAvailable
        }

        let transcriptText = formatTranscript(transcript, speakers: speakers)
        var userMessage = "Transcript:\n\n\(transcriptText)"

        if let context = additionalContext, !context.isEmpty {
            userMessage += "\n\nAdditional context: \(context)"
        }

        let result = try await service.generate(
            systemPrompt: prompt.systemPrompt,
            userMessage: userMessage
        )

        return PromptResult(
            id: UUID(),
            promptName: prompt.name,
            promptBody: prompt.systemPrompt,
            additionalContext: additionalContext,
            llmProvider: provider,
            result: result,
            createdAt: Date()
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
