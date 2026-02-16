import Foundation

struct MapleRecording: Identifiable, Sendable {
    var id: UUID
    var title: String
    var summary: String
    var audioFiles: [String]
    var duration: TimeInterval
    var createdAt: Date
    var modifiedAt: Date
    var speakers: [Speaker]
    var transcript: [TranscriptSegment]
    var promptResults: [PromptResult]

    init(
        id: UUID = UUID(),
        title: String,
        summary: String = "",
        audioFiles: [String] = [],
        duration: TimeInterval = 0,
        createdAt: Date = Date(),
        modifiedAt: Date = Date(),
        speakers: [Speaker] = [],
        transcript: [TranscriptSegment] = [],
        promptResults: [PromptResult] = []
    ) {
        self.id = id
        self.title = title
        self.summary = summary
        self.audioFiles = audioFiles
        self.duration = duration
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.speakers = speakers
        self.transcript = transcript
        self.promptResults = promptResults
    }
}

// MARK: - JSON Metadata Codable (excludes title and summary — those come from Markdown)

extension MapleRecording {
    struct MetadataJSON: Codable {
        var id: UUID
        var audio: [String]
        var duration: TimeInterval
        var createdAt: Date
        var modifiedAt: Date
        var speakers: [Speaker]
        var transcript: [TranscriptSegment]
        var promptResults: [PromptResult]

        enum CodingKeys: String, CodingKey {
            case id, audio, duration, speakers, transcript
            case createdAt = "created_at"
            case modifiedAt = "modified_at"
            case promptResults = "prompt_results"
        }
    }

    var metadata: MetadataJSON {
        MetadataJSON(
            id: id,
            audio: audioFiles,
            duration: duration,
            createdAt: createdAt,
            modifiedAt: modifiedAt,
            speakers: speakers,
            transcript: transcript,
            promptResults: promptResults
        )
    }

    init(title: String, summary: String, metadata: MetadataJSON) {
        self.id = metadata.id
        self.title = title
        self.summary = summary
        self.audioFiles = metadata.audio
        self.duration = metadata.duration
        self.createdAt = metadata.createdAt
        self.modifiedAt = metadata.modifiedAt
        self.speakers = metadata.speakers
        self.transcript = metadata.transcript
        self.promptResults = metadata.promptResults
    }
}
