import AVFoundation
import Foundation
import Observation

struct RecordingResult {
    var micURLs: [URL]
    var systemURLs: [URL]
}

@Observable
final class AudioRecorder {
    var isRecording = false
    var elapsedTime: TimeInterval = 0
    var audioLevel: Float = 0
    var amplitudeSamples: [Float] = []

    #if os(macOS)
    var includeSystemAudio = false
    private var systemCapture = SystemAudioCapture()
    #endif

    private var audioEngine: AVAudioEngine?
    private var timer: Timer?

    // Serial queue for all file writes — eliminates concurrent access to AVAudioFile
    private let writeQueue = DispatchQueue(label: "com.maple.audioWriter", qos: .userInteractive)

    // Mic output (written on writeQueue)
    private var outputFile: AVAudioFile?

    #if os(macOS)
    // System audio output (written on writeQueue)
    private var systemOutputFile: AVAudioFile?
    private var systemChunkURLs: [URL] = []
    #endif

    // Chunking state
    private var recordingId: UUID?
    private var chunkURLs: [URL] = []
    private var chunkIndex = 0
    private var chunkStartTime: Date?
    private var chunkDurationMinutes: Int = 30
    private var isSplitSeeking = false
    private var silenceStartTime: Date?
    private static let silenceThreshold: Float = 0.01
    private static let silenceDuration: TimeInterval = 0.3
    private static let splitWindowSeconds: TimeInterval = 30

    private var inputFormat: AVAudioFormat?
    private var outputSettings: [String: Any] {
        [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 48000.0,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 128000,
        ]
    }

    func startRecording(chunkDurationMinutes: Int = 30) async throws -> URL {
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
        try session.setActive(true)
        #endif

        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        self.inputFormat = format

        self.recordingId = UUID()
        self.chunkDurationMinutes = chunkDurationMinutes
        self.chunkURLs = []
        self.chunkIndex = 0
        #if os(macOS)
        self.systemChunkURLs = []
        #endif

        // Create initial chunk file on writeQueue to ensure serial access
        let url: URL = try writeQueue.sync {
            try createMicChunkFileOnQueue()
        }

        #if os(macOS)
        if includeSystemAudio {
            try writeQueue.sync {
                try createSystemChunkFileOnQueue()
            }
            try await startSystemAudioCapture()
        }
        #endif

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, _ in
            guard let self else { return }
            self.writeQueue.async {
                self.writeMicBufferOnQueue(buffer)
            }
        }

        try engine.start()

        self.audioEngine = engine
        self.isRecording = true
        self.elapsedTime = 0
        self.chunkStartTime = Date()

        let startTime = Date()
        self.timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.elapsedTime = Date().timeIntervalSince(startTime)
            }
        }

        return url
    }

    func stopRecording() -> RecordingResult {
        timer?.invalidate()
        timer = nil

        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil

        // Drain the write queue to ensure all pending writes complete,
        // then nil out the files so no further writes occur.
        writeQueue.sync {
            outputFile = nil
            #if os(macOS)
            systemOutputFile = nil
            #endif
        }

        isRecording = false
        audioLevel = 0
        amplitudeSamples = []
        isSplitSeeking = false
        silenceStartTime = nil

        #if os(macOS)
        Task {
            await systemCapture.stopCapture()
        }
        let result = RecordingResult(micURLs: chunkURLs, systemURLs: systemChunkURLs)
        #else
        let result = RecordingResult(micURLs: chunkURLs, systemURLs: [])
        #endif

        return result
    }

    // MARK: - Buffer Writing (called on writeQueue)

    private func writeMicBufferOnQueue(_ buffer: AVAudioPCMBuffer) {
        try? outputFile?.write(from: buffer)

        // Calculate RMS for audio level
        guard let channelData = buffer.floatChannelData?[0] else { return }
        let frameCount = Int(buffer.frameLength)
        var sum: Float = 0
        for i in 0..<frameCount {
            sum += channelData[i] * channelData[i]
        }
        let rms = sqrt(sum / Float(max(frameCount, 1)))

        Task { @MainActor [weak self] in
            guard let self else { return }
            // Normalize RMS to 0–1 range visible for UI (raw mic RMS is ~0.001–0.05)
            let target = min(rms * 8, 1.0)
            if target > self.audioLevel {
                // Rise quickly to follow speech
                self.audioLevel = self.audioLevel * 0.3 + target * 0.7
            } else {
                // Decay slowly for smooth fade-out
                self.audioLevel = self.audioLevel * 0.85 + target * 0.15
            }
            self.amplitudeSamples.append(min(rms * 3, 1.0))
            self.checkChunkBoundary(rms: rms)
        }
    }

    #if os(macOS)
    private func writeSystemBufferOnQueue(_ buffer: AVAudioPCMBuffer) {
        try? systemOutputFile?.write(from: buffer)
    }
    #endif

    // MARK: - macOS System Audio

    #if os(macOS)
    private func startSystemAudioCapture() async throws {
        await systemCapture.checkPermission()
        guard systemCapture.permissionGranted else {
            throw SystemAudioCaptureError.permissionDenied
        }

        // System audio buffers get written to their own file via writeQueue
        systemCapture.onAudioBuffer = { [weak self] buffer in
            guard let self else { return }
            self.writeQueue.async {
                self.writeSystemBufferOnQueue(buffer)
            }
        }

        try await systemCapture.startCapture()
    }
    #endif

    // MARK: - Chunking

    private func checkChunkBoundary(rms: Float) {
        guard let chunkStartTime else { return }
        let chunkElapsed = Date().timeIntervalSince(chunkStartTime)
        let targetDuration = TimeInterval(chunkDurationMinutes) * 60.0

        // Enter split-seeking mode within ±30s window of target
        if chunkElapsed >= targetDuration - Self.splitWindowSeconds {
            isSplitSeeking = true
        }

        guard isSplitSeeking else { return }

        // Check for silence
        if rms < Self.silenceThreshold {
            if silenceStartTime == nil {
                silenceStartTime = Date()
            }
            if let start = silenceStartTime,
               Date().timeIntervalSince(start) >= Self.silenceDuration {
                // Found a good silence gap — split here
                performChunkSplit()
            }
        } else {
            silenceStartTime = nil
        }

        // Hard cut at target + window
        if chunkElapsed >= targetDuration + Self.splitWindowSeconds {
            performChunkSplit()
        }
    }

    private func performChunkSplit() {
        isSplitSeeking = false
        silenceStartTime = nil
        chunkStartTime = Date()

        writeQueue.async { [weak self] in
            guard let self else { return }
            // Close current files
            self.outputFile = nil
            #if os(macOS)
            self.systemOutputFile = nil
            #endif

            do {
                try self.createMicChunkFileOnQueue()
                #if os(macOS)
                if self.includeSystemAudio {
                    try self.createSystemChunkFileOnQueue()
                }
                #endif
            } catch {
                print("Failed to create new chunk: \(error)")
            }
        }
    }

    // MARK: - Chunk File Creation (called on writeQueue)

    @discardableResult
    private func createMicChunkFileOnQueue() throws -> URL {
        guard let inputFormat, let recordingId else {
            throw NSError(domain: "AudioRecorder", code: 1, userInfo: [NSLocalizedDescriptionKey: "Not initialized"])
        }

        let tempDir = FileManager.default.temporaryDirectory
        let baseName = recordingId.uuidString
        let fileName: String
        if chunkURLs.isEmpty {
            fileName = "\(baseName).m4a"
        } else {
            // Rename first chunk if this is the second chunk
            if chunkURLs.count == 1 {
                let oldURL = chunkURLs[0]
                let newURL = tempDir.appendingPathComponent("\(baseName)_part1.m4a")
                if oldURL.lastPathComponent != newURL.lastPathComponent {
                    try? FileManager.default.moveItem(at: oldURL, to: newURL)
                    chunkURLs[0] = newURL
                }
                #if os(macOS)
                // Also rename system chunk if it exists
                if systemChunkURLs.count == 1 {
                    let oldSysURL = systemChunkURLs[0]
                    let newSysURL = tempDir.appendingPathComponent("\(baseName)_sys.m4a")
                    if oldSysURL.lastPathComponent != newSysURL.lastPathComponent {
                        try? FileManager.default.moveItem(at: oldSysURL, to: newSysURL)
                        systemChunkURLs[0] = newSysURL
                    }
                }
                #endif
            }
            fileName = "\(baseName)_part\(chunkURLs.count + 1).m4a"
        }
        let url = tempDir.appendingPathComponent(fileName)

        let file = try AVAudioFile(
            forWriting: url,
            settings: outputSettings,
            commonFormat: inputFormat.commonFormat,
            interleaved: inputFormat.isInterleaved
        )

        self.outputFile = file
        chunkURLs.append(url)
        chunkIndex = chunkURLs.count - 1

        return url
    }

    #if os(macOS)
    @discardableResult
    private func createSystemChunkFileOnQueue() throws -> URL {
        guard let recordingId else {
            throw NSError(domain: "AudioRecorder", code: 1, userInfo: [NSLocalizedDescriptionKey: "Not initialized"])
        }

        let tempDir = FileManager.default.temporaryDirectory
        let baseName = recordingId.uuidString
        let fileName: String
        if systemChunkURLs.isEmpty {
            fileName = "\(baseName)_sys.m4a"
        } else {
            // Rename first system chunk if this is the second chunk
            if systemChunkURLs.count == 1 {
                let oldURL = systemChunkURLs[0]
                let newURL = tempDir.appendingPathComponent("\(baseName)_sys_part1.m4a")
                if oldURL.lastPathComponent != newURL.lastPathComponent {
                    try? FileManager.default.moveItem(at: oldURL, to: newURL)
                    systemChunkURLs[0] = newURL
                }
            }
            fileName = "\(baseName)_sys_part\(systemChunkURLs.count + 1).m4a"
        }
        let url = tempDir.appendingPathComponent(fileName)

        // System audio: 48kHz mono Float32 (matches SCStream output)
        let systemFormat = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 1)!
        let file = try AVAudioFile(
            forWriting: url,
            settings: outputSettings,
            commonFormat: systemFormat.commonFormat,
            interleaved: systemFormat.isInterleaved
        )

        self.systemOutputFile = file
        systemChunkURLs.append(url)

        return url
    }
    #endif
}
