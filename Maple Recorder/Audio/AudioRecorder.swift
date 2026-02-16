import AVFoundation
import Foundation
import Observation

@Observable
final class AudioRecorder {
    var isRecording = false
    var elapsedTime: TimeInterval = 0
    var audioLevel: Float = 0
    var amplitudeSamples: [Float] = []

    private var audioEngine: AVAudioEngine?
    private var outputFile: AVAudioFile?
    private var outputURL: URL?
    private var timer: Timer?

    func startRecording() async throws -> URL {
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
        try session.setActive(true)
        #endif

        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

        // Create temp file for recording
        let tempDir = FileManager.default.temporaryDirectory
        let fileName = "\(UUID().uuidString).m4a"
        let url = tempDir.appendingPathComponent(fileName)

        // Set up output as AAC M4A
        let outputSettings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 48000.0,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 128000,
        ]

        let file = try AVAudioFile(
            forWriting: url,
            settings: outputSettings,
            commonFormat: inputFormat.commonFormat,
            interleaved: inputFormat.isInterleaved
        )

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            try? file.write(from: buffer)

            // Calculate RMS for audio level
            guard let channelData = buffer.floatChannelData?[0] else { return }
            let frameCount = Int(buffer.frameLength)
            var sum: Float = 0
            for i in 0..<frameCount {
                sum += channelData[i] * channelData[i]
            }
            let rms = sqrt(sum / Float(max(frameCount, 1)))
            Task { @MainActor [weak self] in
                self?.audioLevel = rms
                self?.amplitudeSamples.append(min(rms * 3, 1.0))
            }
        }

        try engine.start()

        self.audioEngine = engine
        self.outputFile = file
        self.outputURL = url
        self.isRecording = true
        self.elapsedTime = 0

        let startTime = Date()
        self.timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.elapsedTime = Date().timeIntervalSince(startTime)
            }
        }

        return url
    }

    func stopRecording() -> URL? {
        timer?.invalidate()
        timer = nil

        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        outputFile = nil
        isRecording = false
        audioLevel = 0
        amplitudeSamples = []

        return outputURL
    }
}
