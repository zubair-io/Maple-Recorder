import AVFoundation
import Foundation
import Observation

@Observable
final class AudioRecorder {
    var isRecording = false
    var elapsedTime: TimeInterval = 0
    var audioLevel: Float = 0
    var amplitudeSamples: [Float] = []

    #if os(macOS)
    var includeSystemAudio = false
    private var systemCapture = SystemAudioCapture()
    private var mixer = AudioMixer()
    #endif

    private var audioEngine: AVAudioEngine?
    private var outputFile: AVAudioFile?
    private var timer: Timer?

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

        let url = try createChunkFile()

        #if os(macOS)
        if includeSystemAudio {
            try await startSystemAudioCapture()
        }
        #endif

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, _ in
            guard let self else { return }
            self.writeBuffer(buffer)
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

    func stopRecording() -> [URL] {
        timer?.invalidate()
        timer = nil

        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        outputFile = nil
        isRecording = false
        audioLevel = 0
        amplitudeSamples = []
        isSplitSeeking = false
        silenceStartTime = nil

        #if os(macOS)
        Task {
            await systemCapture.stopCapture()
        }
        #endif

        return chunkURLs
    }

    // MARK: - Buffer Writing

    private func writeBuffer(_ buffer: AVAudioPCMBuffer) {
        try? self.outputFile?.write(from: buffer)

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
            self.audioLevel = rms
            self.amplitudeSamples.append(min(rms * 3, 1.0))
            self.checkChunkBoundary(rms: rms)
        }
    }

    // MARK: - macOS System Audio

    #if os(macOS)
    private func startSystemAudioCapture() async throws {
        await systemCapture.checkPermission()
        guard systemCapture.permissionGranted else {
            throw SystemAudioCaptureError.permissionDenied
        }

        // System audio buffers get written to the file too
        systemCapture.onAudioBuffer = { [weak self] buffer in
            guard let self else { return }
            try? self.outputFile?.write(from: buffer)
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
        outputFile = nil
        isSplitSeeking = false
        silenceStartTime = nil
        chunkStartTime = Date()

        do {
            _ = try createChunkFile()
        } catch {
            print("Failed to create new chunk: \(error)")
        }
    }

    private func createChunkFile() throws -> URL {
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
}
