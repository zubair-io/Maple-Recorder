#if os(watchOS)
import AVFoundation
import Foundation
import Observation

/// Simplified recorder for watchOS using AVAudioRecorder (lower memory than AVAudioEngine).
/// Records compressed M4A directly to minimize file size for WatchConnectivity transfer.
@Observable
final class WatchAudioRecorder: NSObject, AVAudioRecorderDelegate, @unchecked Sendable {
    var isRecording = false
    var elapsedTime: TimeInterval = 0
    var audioLevel: Float = 0

    private var audioRecorder: AVAudioRecorder?
    private var timer: Timer?
    private var recordingURL: URL?

    private var outputSettings: [String: Any] {
        [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44100.0,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 64000, // Lower bitrate for smaller transfer size
        ]
    }

    func startRecording() throws -> URL {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .default)
        try session.setActive(true)

        let tempDir = FileManager.default.temporaryDirectory
        let fileName = "\(UUID().uuidString).m4a"
        let url = tempDir.appendingPathComponent(fileName)

        let recorder = try AVAudioRecorder(url: url, settings: outputSettings)
        recorder.delegate = self
        recorder.isMeteringEnabled = true
        recorder.record()

        self.audioRecorder = recorder
        self.recordingURL = url
        self.isRecording = true
        self.elapsedTime = 0

        let startTime = Date()
        self.timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.audioRecorder?.updateMeters()
            let power = self.audioRecorder?.averagePower(forChannel: 0) ?? -160
            // Convert dB to linear (0-1 range)
            let linear = max(0, min(1, (power + 50) / 50))
            Task { @MainActor [weak self] in
                self?.audioLevel = linear
                self?.elapsedTime = Date().timeIntervalSince(startTime)
            }
        }

        return url
    }

    func stopRecording() -> URL? {
        timer?.invalidate()
        timer = nil

        audioRecorder?.stop()
        audioRecorder = nil
        isRecording = false
        audioLevel = 0

        let session = AVAudioSession.sharedInstance()
        try? session.setActive(false)

        return recordingURL
    }

    // MARK: - AVAudioRecorderDelegate

    nonisolated func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        Task { @MainActor [weak self] in
            self?.isRecording = false
        }
    }
}
#endif
