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
    var tags: [String]

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
        promptResults: [PromptResult] = [],
        tags: [String] = []
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
        self.tags = tags
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
        var tags: [String]

        enum CodingKeys: String, CodingKey {
            case id, audio, duration, speakers, transcript, tags
            case createdAt = "created_at"
            case modifiedAt = "modified_at"
            case promptResults = "prompt_results"
        }

        init(
            id: UUID,
            audio: [String],
            duration: TimeInterval,
            createdAt: Date,
            modifiedAt: Date,
            speakers: [Speaker],
            transcript: [TranscriptSegment],
            promptResults: [PromptResult],
            tags: [String]
        ) {
            self.id = id
            self.audio = audio
            self.duration = duration
            self.createdAt = createdAt
            self.modifiedAt = modifiedAt
            self.speakers = speakers
            self.transcript = transcript
            self.promptResults = promptResults
            self.tags = tags
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decode(UUID.self, forKey: .id)
            audio = try container.decode([String].self, forKey: .audio)
            duration = try container.decode(TimeInterval.self, forKey: .duration)
            createdAt = try container.decode(Date.self, forKey: .createdAt)
            modifiedAt = try container.decode(Date.self, forKey: .modifiedAt)
            speakers = try container.decode([Speaker].self, forKey: .speakers)
            transcript = try container.decode([TranscriptSegment].self, forKey: .transcript)
            promptResults = try container.decode([PromptResult].self, forKey: .promptResults)
            tags = try container.decodeIfPresent([String].self, forKey: .tags) ?? []
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
            promptResults: promptResults,
            tags: tags
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
        self.tags = metadata.tags
    }
}
