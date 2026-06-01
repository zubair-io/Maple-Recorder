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

        // Run the user's prompt over the whole transcript via the shared map-reduce
        // engine, so even long transcripts fit the provider's context window
        // (on-device Foundation Models is limited to 4,096 tokens).
        let mapPrompt = """
            \(prompt.systemPrompt)

            You are given one section of a longer transcript. Respond for this section only; \
            your response will later be combined with responses to the other sections.
            """
        let reducePrompt = """
            You are combining responses, each covering a different section of the same \
            transcript, into one cohesive final response. Follow this instruction for the \
            combined result:

            \(prompt.systemPrompt)

            Merge the sectioned responses below into a single coherent answer. Do not mention \
            that the transcript was processed in sections.
            """

        let result = try await TranscriptLLM.run(
            transcript: transcript,
            speakers: speakers,
            provider: provider,
            service: service,
            prompts: .init(single: prompt.systemPrompt, map: mapPrompt, reduce: reducePrompt),
            additionalContext: additionalContext
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
}
#endif
