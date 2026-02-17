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

        let response = try await service.generate(
            systemPrompt: systemPrompt,
            userMessage: transcriptText
        )

        return parseResponse(response)
    }

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
