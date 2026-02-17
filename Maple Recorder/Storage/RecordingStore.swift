import Foundation
import Observation

@Observable
final class RecordingStore {
    var recordings: [MapleRecording] = []

    private let fileManager = FileManager.default

    init() {
        try? StorageLocation.ensureDirectoryExists()
        loadRecordings()
    }

    // For testing with a custom directory
    init(directory: URL) {
        self.overrideDirectory = directory
        if !fileManager.fileExists(atPath: directory.path()) {
            try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        loadRecordings()
    }

    private var overrideDirectory: URL?

    private var recordingsURL: URL {
        overrideDirectory ?? StorageLocation.recordingsURL
    }

    func loadRecordings() {
        guard let files = try? fileManager.contentsOfDirectory(
            at: recordingsURL,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: .skipsHiddenFiles
        ) else {
            recordings = []
            return
        }

        recordings = files
            .filter { $0.pathExtension == "md" }
            .compactMap { url -> MapleRecording? in
                guard let data = try? Data(contentsOf: url),
                      let markdown = String(data: data, encoding: .utf8) else {
                    return nil
                }
                return MarkdownSerializer.deserialize(markdown)
            }
            .sorted { $0.createdAt > $1.createdAt }
    }

    func save(_ recording: MapleRecording) throws {
        let markdown = MarkdownSerializer.serialize(recording)
        let fileURL = recordingsURL.appendingPathComponent("\(recording.id.uuidString).md")
        try markdown.write(to: fileURL, atomically: true, encoding: .utf8)

        if let index = recordings.firstIndex(where: { $0.id == recording.id }) {
            recordings[index] = recording
        } else {
            recordings.append(recording)
            recordings.sort { $0.createdAt > $1.createdAt }
        }
    }

    func delete(_ recording: MapleRecording) throws {
        let mdURL = recordingsURL.appendingPathComponent("\(recording.id.uuidString).md")
        if fileManager.fileExists(atPath: mdURL.path()) {
            try fileManager.removeItem(at: mdURL)
        }

        for audioFile in recording.audioFiles {
            let audioURL = recordingsURL.appendingPathComponent(audioFile)
            if fileManager.fileExists(atPath: audioURL.path()) {
                try fileManager.removeItem(at: audioURL)
            }
        }

        recordings.removeAll { $0.id == recording.id }
    }

    func update(_ recording: MapleRecording) throws {
        var updated = recording
        updated.modifiedAt = Date()
        try save(updated)
    }

    #if !os(watchOS)
    func processRecording(
        _ recording: MapleRecording,
        pipeline: ProcessingPipeline,
        transcription: TranscriptionManager,
        diarization: DiarizationManager,
        summarizationProvider: LLMProvider = .none
    ) async throws {
        let audioURLs = recording.audioFiles.map { recordingsURL.appendingPathComponent($0) }
        let result = try await pipeline.process(
            audioURLs: audioURLs,
            transcriptionManager: transcription,
            diarizationManager: diarization,
            summarizationProvider: summarizationProvider
        )
        var updated = recording
        updated.transcript = result.segments
        updated.speakers = result.speakers
        updated.summary = result.summary
        if !result.generatedTitle.isEmpty {
            updated.title = result.generatedTitle
        }
        updated.modifiedAt = Date()
        try save(updated)
    }
    #endif
}
