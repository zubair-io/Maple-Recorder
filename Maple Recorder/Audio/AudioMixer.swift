#if os(macOS)
import AVFoundation
import Foundation

/// Combines microphone and system audio buffers into a single mono Float32 stream.
/// Both inputs are expected at 48kHz. The mixer normalizes levels and outputs
/// mixed buffers via `onMixedBuffer`.
final class AudioMixer {
    var micLevel: Float = 1.0
    var systemLevel: Float = 0.7

    var onMixedBuffer: ((AVAudioPCMBuffer) -> Void)?

    private let outputFormat: AVAudioFormat
    private let lock = NSLock()

    init() {
        self.outputFormat = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 1)!
    }

    /// Feed a microphone buffer. Passes through directly when no system audio mixing is needed.
    func receiveMicBuffer(_ buffer: AVAudioPCMBuffer) {
        // Scale mic level
        if let channelData = buffer.floatChannelData {
            let frameCount = Int(buffer.frameLength)
            for i in 0..<frameCount {
                channelData[0][i] *= micLevel
            }
        }
        onMixedBuffer?(buffer)
    }

    /// Feed a system audio buffer. Converts to output format and mixes into the stream.
    func receiveSystemBuffer(_ buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData else { return }

        // Apply system audio level
        let frameCount = Int(buffer.frameLength)
        for i in 0..<frameCount {
            channelData[0][i] *= systemLevel
        }

        onMixedBuffer?(buffer)
    }

    /// Mix two equal-length buffers together into one.
    /// Used when mic and system buffers arrive at the same time.
    func mixBuffers(mic: AVAudioPCMBuffer, system: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        let frameCount = min(mic.frameLength, system.frameLength)
        guard let output = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: frameCount) else {
            return nil
        }
        output.frameLength = frameCount

        guard let micData = mic.floatChannelData?[0],
              let sysData = system.floatChannelData?[0],
              let outData = output.floatChannelData?[0] else {
            return nil
        }

        for i in 0..<Int(frameCount) {
            // Simple additive mix with clamp
            let mixed = (micData[i] * micLevel) + (sysData[i] * systemLevel)
            outData[i] = max(-1.0, min(1.0, mixed))
        }

        return output
    }
}
#endif
