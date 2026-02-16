import Testing
import Foundation
@testable import Maple_Recorder

struct MapleRecordingTests {

    private func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .sortedKeys
        return encoder
    }

    private func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    @Test func metadataRoundTrip() throws {
        let date = Date(timeIntervalSince1970: 1700000000)
        let recording = MapleRecording(
            title: "Test Recording",
            summary: "A summary",
            audioFiles: ["test.m4a"],
            duration: 120.5,
            createdAt: date,
            modifiedAt: date,
            speakers: [
                Speaker(id: "s0", displayName: "Alice", color: "speaker0", embedding: nil)
            ],
            transcript: [
                TranscriptSegment(
                    speakerId: "s0",
                    start: 0.0,
                    end: 5.0,
                    text: "Hello world",
                    words: [
                        WordTiming(word: "Hello", start: 0.0, end: 0.5),
                        WordTiming(word: "world", start: 0.6, end: 1.0),
                    ]
                )
            ],
            promptResults: []
        )

        let encoder = makeEncoder()
        let data = try encoder.encode(recording.metadata)

        let decoder = makeDecoder()
        let decoded = try decoder.decode(MapleRecording.MetadataJSON.self, from: data)

        #expect(decoded.id == recording.id)
        #expect(decoded.audio == ["test.m4a"])
        #expect(decoded.duration == 120.5)
        #expect(decoded.speakers.count == 1)
        #expect(decoded.speakers[0].displayName == "Alice")
        #expect(decoded.transcript.count == 1)
        #expect(decoded.transcript[0].text == "Hello world")
        #expect(decoded.transcript[0].words.count == 2)
    }

    @Test func defaultValues() {
        let recording = MapleRecording(title: "Untitled")

        #expect(recording.summary == "")
        #expect(recording.audioFiles.isEmpty)
        #expect(recording.duration == 0)
        #expect(recording.speakers.isEmpty)
        #expect(recording.transcript.isEmpty)
        #expect(recording.promptResults.isEmpty)
    }

    @Test func emptyTranscriptEncoding() throws {
        let recording = MapleRecording(title: "Empty")

        let encoder = makeEncoder()
        let data = try encoder.encode(recording.metadata)

        let decoder = makeDecoder()
        let decoded = try decoder.decode(MapleRecording.MetadataJSON.self, from: data)

        #expect(decoded.transcript.isEmpty)
        #expect(decoded.speakers.isEmpty)
        #expect(decoded.promptResults.isEmpty)
    }
}
