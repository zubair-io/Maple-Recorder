import Testing
import Foundation
@testable import Maple_Recorder

struct RecordingStoreTests {

    private func makeTempDirectory() throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("MapleRecorderTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        return tempDir
    }

    private func cleanup(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    @Test func saveAndLoad() throws {
        let dir = try makeTempDirectory()
        defer { cleanup(dir) }

        let store = RecordingStore(directory: dir)
        let recording = MapleRecording(
            title: "Test Recording",
            summary: "A test",
            audioFiles: ["test.m4a"],
            duration: 60.0
        )

        try store.save(recording)
        #expect(store.recordings.count == 1)
        #expect(store.recordings[0].title == "Test Recording")

        // Create a new store from the same directory to verify persistence
        let store2 = RecordingStore(directory: dir)
        #expect(store2.recordings.count == 1)
        #expect(store2.recordings[0].id == recording.id)
        #expect(store2.recordings[0].title == "Test Recording")
    }

    @Test func deleteRemovesFile() throws {
        let dir = try makeTempDirectory()
        defer { cleanup(dir) }

        let store = RecordingStore(directory: dir)
        let recording = MapleRecording(
            title: "To Delete",
            audioFiles: ["delete.m4a"],
            duration: 10.0
        )

        try store.save(recording)
        #expect(store.recordings.count == 1)

        try store.delete(recording)
        #expect(store.recordings.isEmpty)

        // Verify file is gone
        let mdPath = dir.appendingPathComponent("\(recording.id.uuidString).md").path()
        #expect(!FileManager.default.fileExists(atPath: mdPath))
    }

    @Test func emptyDirectoryReturnsEmpty() throws {
        let dir = try makeTempDirectory()
        defer { cleanup(dir) }

        let store = RecordingStore(directory: dir)
        #expect(store.recordings.isEmpty)
    }

    @Test func multipleRecordingsSortedByDateDescending() throws {
        let dir = try makeTempDirectory()
        defer { cleanup(dir) }

        let store = RecordingStore(directory: dir)

        let older = MapleRecording(
            title: "Older",
            audioFiles: ["old.m4a"],
            duration: 30.0,
            createdAt: Date(timeIntervalSince1970: 1000)
        )
        let newer = MapleRecording(
            title: "Newer",
            audioFiles: ["new.m4a"],
            duration: 30.0,
            createdAt: Date(timeIntervalSince1970: 2000)
        )

        try store.save(older)
        try store.save(newer)

        #expect(store.recordings.count == 2)
        #expect(store.recordings[0].title == "Newer")
        #expect(store.recordings[1].title == "Older")
    }
}
