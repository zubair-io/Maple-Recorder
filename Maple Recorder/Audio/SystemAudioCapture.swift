#if os(macOS)
import AVFoundation
import Foundation
import Observation
import ScreenCaptureKit

@Observable
final class SystemAudioCapture: NSObject, @unchecked Sendable {
    var isCapturing = false
    var permissionGranted = false

    private var stream: SCStream?
    private var streamOutput: AudioStreamOutput?
    private(set) var audioFormat: AVAudioFormat?

    /// Callback invoked on each captured audio buffer
    var onAudioBuffer: ((AVAudioPCMBuffer) -> Void)?

    func checkPermission() async {
        do {
            // Requesting shareable content checks/triggers the permission prompt
            _ = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
            permissionGranted = true
        } catch {
            permissionGranted = false
        }
    }

    func startCapture() async throws {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)

        guard let display = content.displays.first else {
            throw SystemAudioCaptureError.noDisplay
        }

        // Audio-only: exclude all windows and apps from video capture
        let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])

        let config = SCStreamConfiguration()
        config.capturesAudio = true
        config.excludesCurrentProcessAudio = true
        // No video capture needed
        config.width = 2
        config.height = 2
        config.minimumFrameInterval = CMTime(value: 1, timescale: 1)

        // Audio format: 48kHz mono to match our recording pipeline
        config.sampleRate = 48000
        config.channelCount = 1

        let output = AudioStreamOutput { [weak self] buffer in
            self?.onAudioBuffer?(buffer)
        }
        self.streamOutput = output

        let stream = SCStream(filter: filter, configuration: config, delegate: nil)
        try stream.addStreamOutput(output, type: .audio, sampleHandlerQueue: .global(qos: .userInteractive))
        try await stream.startCapture()

        self.stream = stream
        self.audioFormat = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 1)
        self.isCapturing = true
    }

    func stopCapture() async {
        if let stream {
            try? await stream.stopCapture()
        }
        stream = nil
        streamOutput = nil
        isCapturing = false
    }
}

// MARK: - Stream Output

private final class AudioStreamOutput: NSObject, SCStreamOutput, Sendable {
    let handler: @Sendable (AVAudioPCMBuffer) -> Void

    init(handler: @escaping @Sendable (AVAudioPCMBuffer) -> Void) {
        self.handler = handler
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio else { return }
        guard sampleBuffer.isValid, sampleBuffer.numSamples > 0 else { return }

        guard let formatDescription = sampleBuffer.formatDescription,
              let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription) else {
            return
        }

        let audioFormat = AVAudioFormat(streamDescription: asbd)
        guard let audioFormat else { return }

        guard let blockBuffer = sampleBuffer.dataBuffer else { return }
        let frameCount = AVAudioFrameCount(sampleBuffer.numSamples)

        guard let pcmBuffer = AVAudioPCMBuffer(pcmFormat: audioFormat, frameCapacity: frameCount) else {
            return
        }
        pcmBuffer.frameLength = frameCount

        var dataPointer: UnsafeMutablePointer<Int8>?
        var totalLength: Int = 0
        let status = CMBlockBufferGetDataPointer(blockBuffer, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &totalLength, dataPointerOut: &dataPointer)

        guard status == kCMBlockBufferNoErr, let dataPointer else { return }

        let byteCount = min(totalLength, Int(frameCount) * Int(audioFormat.streamDescription.pointee.mBytesPerFrame))
        if let channelData = pcmBuffer.floatChannelData {
            memcpy(channelData[0], dataPointer, byteCount)
        } else if let int16Data = pcmBuffer.int16ChannelData {
            memcpy(int16Data[0], dataPointer, byteCount)
        }

        handler(pcmBuffer)
    }
}

// MARK: - Errors

enum SystemAudioCaptureError: LocalizedError {
    case noDisplay
    case permissionDenied

    var errorDescription: String? {
        switch self {
        case .noDisplay: "No display found for audio capture."
        case .permissionDenied: "Screen Recording permission is required to capture system audio."
        }
    }
}
#endif
