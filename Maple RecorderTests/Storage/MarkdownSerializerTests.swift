import Testing
import Foundation
@testable import Maple_Recorder

struct MarkdownSerializerTests {

    private let fixedDate = Date(timeIntervalSince1970: 1700000000)

    private func makeSampleRecording() -> MapleRecording {
        MapleRecording(
            title: "Team Standup",
            summary: "Discussion about Q4 goals and sprint planning.",
            audioFiles: ["abc123.m4a"],
            duration: 300.0,
            createdAt: fixedDate,
            modifiedAt: fixedDate,
            speakers: [
                Speaker(id: "s0", displayName: "Alice", color: "speaker0", embedding: nil),
                Speaker(id: "s1", displayName: "Bob", color: "speaker1", embedding: nil),
            ],
            transcript: [
                TranscriptSegment(
                    speakerId: "s0",
                    start: 0.0,
                    end: 3.0,
                    text: "Good morning everyone",
                    words: [
                        WordTiming(word: "Good", start: 0.0, end: 0.3),
                        WordTiming(word: "morning", start: 0.4, end: 0.8),
                        WordTiming(word: "everyone", start: 0.9, end: 1.5),
                    ]
                ),
            ],
            promptResults: []
        )
    }

    @Test func roundTrip() throws {
        let original = makeSampleRecording()
        let markdown = MarkdownSerializer.serialize(original)
        let deserialized = MarkdownSerializer.deserialize(markdown)

        #expect(deserialized != nil)
        let result = deserialized!

        #expect(result.id == original.id)
        #expect(result.title == "Team Standup")
        #expect(result.summary == "Discussion about Q4 goals and sprint planning.")
        #expect(result.audioFiles == ["abc123.m4a"])
        #expect(result.duration == 300.0)
        #expect(result.speakers.count == 2)
        #expect(result.speakers[0].displayName == "Alice")
        #expect(result.transcript.count == 1)
        #expect(result.transcript[0].text == "Good morning everyone")
        #expect(result.transcript[0].words.count == 3)
    }

    @Test func emptyTranscript() throws {
        let recording = MapleRecording(
            title: "Silent Recording",
            summary: "",
            audioFiles: ["empty.m4a"],
            duration: 10.0,
            createdAt: fixedDate,
            modifiedAt: fixedDate
        )

        let markdown = MarkdownSerializer.serialize(recording)
        let result = MarkdownSerializer.deserialize(markdown)

        #expect(result != nil)
        #expect(result!.transcript.isEmpty)
        #expect(result!.speakers.isEmpty)
    }

    @Test func multiPartAudio() throws {
        let recording = MapleRecording(
            title: "Long Meeting",
            summary: "A very long meeting.",
            audioFiles: ["part1.m4a", "part2.m4a", "part3.m4a"],
            duration: 5400.0,
            createdAt: fixedDate,
            modifiedAt: fixedDate
        )

        let markdown = MarkdownSerializer.serialize(recording)
        let result = MarkdownSerializer.deserialize(markdown)

        #expect(result != nil)
        #expect(result!.audioFiles.count == 3)
        #expect(result!.audioFiles == ["part1.m4a", "part2.m4a", "part3.m4a"])
    }

    @Test func promptResults() throws {
        let recording = MapleRecording(
            title: "Meeting",
            summary: "Summary here.",
            audioFiles: ["test.m4a"],
            duration: 60.0,
            createdAt: fixedDate,
            modifiedAt: fixedDate,
            promptResults: [
                PromptResult(
                    id: UUID(),
                    promptName: "Action Items",
                    promptBody: "List action items",
                    llmProvider: .appleFoundationModels,
                    result: "1. Review PR\n2. Update docs",
                    createdAt: fixedDate
                )
            ]
        )

        let markdown = MarkdownSerializer.serialize(recording)

        #expect(markdown.contains("## Action Items"))
        #expect(markdown.contains("Apple Foundation Models"))
        #expect(markdown.contains("1. Review PR"))

        // Deserialize should still work (prompt results come from JSON metadata)
        let result = MarkdownSerializer.deserialize(markdown)
        #expect(result != nil)
        #expect(result!.promptResults.count == 1)
        #expect(result!.promptResults[0].promptName == "Action Items")
    }

    @Test func emptySummary() throws {
        let recording = MapleRecording(
            title: "Quick Note",
            summary: "",
            audioFiles: ["note.m4a"],
            duration: 5.0,
            createdAt: fixedDate,
            modifiedAt: fixedDate
        )

        let markdown = MarkdownSerializer.serialize(recording)
        let result = MarkdownSerializer.deserialize(markdown)

        #expect(result != nil)
        #expect(result!.title == "Quick Note")
        #expect(result!.summary == "")
    }

    @Test func specialCharactersInTitle() throws {
        let recording = MapleRecording(
            title: "Meeting — Q4 \"Goals\" & Plans",
            summary: "Important discussion.",
            audioFiles: ["test.m4a"],
            duration: 60.0,
            createdAt: fixedDate,
            modifiedAt: fixedDate
        )

        let markdown = MarkdownSerializer.serialize(recording)
        let result = MarkdownSerializer.deserialize(markdown)

        #expect(result != nil)
        #expect(result!.title == "Meeting — Q4 \"Goals\" & Plans")
    }

    @Test func datePreservesISO8601() throws {
        let recording = MapleRecording(
            title: "Date Test",
            audioFiles: ["test.m4a"],
            createdAt: fixedDate,
            modifiedAt: fixedDate
        )

        let markdown = MarkdownSerializer.serialize(recording)
        #expect(markdown.contains("2023-11-14"))

        let result = MarkdownSerializer.deserialize(markdown)
        #expect(result != nil)
        // Compare to within 1 second to account for encoding precision
        #expect(abs(result!.createdAt.timeIntervalSince1970 - fixedDate.timeIntervalSince1970) < 1)
    }
}
