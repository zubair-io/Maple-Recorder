#if os(macOS)
import Accelerate
import AVFoundation
import Foundation

/// Detects the Google Meet end-call chime by analyzing system audio for a
/// two-tone descending pattern (~783 Hz G5 → ~659 Hz E5 within 0.8 seconds).
/// Uses Accelerate vDSP FFT on a dedicated queue to avoid blocking audio writes.
final class EndCallChimeDetector: @unchecked Sendable {
    var onChimeDetected: (() -> Void)?

    // FFT parameters: 4096-point at 48 kHz → ~11.7 Hz bin resolution
    private let fftSize = 4096
    private let sampleRate: Double = 48000.0
    private let analysisQueue = DispatchQueue(label: "com.maple.chimeDetector", qos: .utility)

    // Frequency targets (Hz) with tolerance
    private static let tone1Frequency: Double = 783.0   // G5
    private static let tone2Frequency: Double = 659.0   // E5
    private static let frequencyTolerance: Double = 30.0 // ±30 Hz

    // Timing: tone2 must follow tone1 within this window
    private static let maxToneGap: TimeInterval = 0.8

    // Cooldown to prevent re-triggers on the same chime
    private static let cooldownDuration: TimeInterval = 10.0

    // Ring buffer to accumulate small SCStream buffers into FFT-sized chunks
    private var ringBuffer: [Float] = []

    // Detection state
    private var tone1DetectedAt: Date?
    private var lastChimeAt: Date?

    // vDSP FFT setup (created once, reused)
    private let fftSetup: FFTSetup?
    private let log2n: vDSP_Length

    init() {
        log2n = vDSP_Length(log2(Double(fftSize)))
        fftSetup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2))
        ringBuffer.reserveCapacity(fftSize * 2)
    }

    deinit {
        if let fftSetup {
            vDSP_destroy_fftsetup(fftSetup)
        }
    }

    /// Feed system audio buffers here from the SCStream callback.
    func analyzeBuffer(_ buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData?[0] else { return }
        let frameCount = Int(buffer.frameLength)

        // Copy samples to avoid dangling pointer across dispatch
        let samples = Array(UnsafeBufferPointer(start: channelData, count: frameCount))

        analysisQueue.async { [weak self] in
            self?.accumulateAndAnalyze(samples)
        }
    }

    // MARK: - Private

    private func accumulateAndAnalyze(_ samples: [Float]) {
        ringBuffer.append(contentsOf: samples)

        // Process as many full FFT frames as we have
        while ringBuffer.count >= fftSize {
            let frame = Array(ringBuffer.prefix(fftSize))
            ringBuffer.removeFirst(fftSize)
            analyzeFrame(frame)
        }

        // Prevent unbounded growth (keep at most 2× FFT size)
        if ringBuffer.count > fftSize * 2 {
            ringBuffer.removeFirst(ringBuffer.count - fftSize)
        }
    }

    private func analyzeFrame(_ frame: [Float]) {
        guard let fftSetup else { return }

        // Check cooldown
        if let lastChime = lastChimeAt,
           Date().timeIntervalSince(lastChime) < Self.cooldownDuration {
            return
        }

        // Apply Hann window
        var windowed = [Float](repeating: 0, count: fftSize)
        var window = [Float](repeating: 0, count: fftSize)
        vDSP_hann_window(&window, vDSP_Length(fftSize), Int32(vDSP_HANN_NORM))
        vDSP_vmul(frame, 1, window, 1, &windowed, 1, vDSP_Length(fftSize))

        // Split into real/imaginary for FFT
        let halfSize = fftSize / 2
        var realPart = [Float](repeating: 0, count: halfSize)
        var imagPart = [Float](repeating: 0, count: halfSize)

        realPart.withUnsafeMutableBufferPointer { realBuf in
            imagPart.withUnsafeMutableBufferPointer { imagBuf in
                var splitComplex = DSPSplitComplex(
                    realp: realBuf.baseAddress!,
                    imagp: imagBuf.baseAddress!
                )

                // Pack interleaved data into split complex
                windowed.withUnsafeBufferPointer { windowedBuf in
                    windowedBuf.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: halfSize) { complexPtr in
                        vDSP_ctoz(complexPtr, 2, &splitComplex, 1, vDSP_Length(halfSize))
                    }
                }

                // Forward FFT
                vDSP_fft_zrip(fftSetup, &splitComplex, 1, log2n, FFTDirection(kFFTDirection_Forward))

                // Compute magnitudes
                var magnitudes = [Float](repeating: 0, count: halfSize)
                vDSP_zvmags(&splitComplex, 1, &magnitudes, 1, vDSP_Length(halfSize))

                checkTones(magnitudes: magnitudes)
            }
        }
    }

    private func checkTones(magnitudes: [Float]) {
        let binResolution = sampleRate / Double(fftSize)

        // Find the dominant frequency (bin with highest magnitude, ignoring DC and very low bins)
        let minBin = Int(200.0 / binResolution) // Ignore below 200 Hz
        let maxBin = min(magnitudes.count, Int(2000.0 / binResolution)) // Ignore above 2 kHz

        guard minBin < maxBin else { return }

        var peakBin = minBin
        var peakMag: Float = 0
        for i in minBin..<maxBin {
            if magnitudes[i] > peakMag {
                peakMag = magnitudes[i]
                peakBin = i
            }
        }

        // Require a minimum magnitude to filter silence/noise
        guard peakMag > 1e-4 else { return }

        let peakFrequency = Double(peakBin) * binResolution

        // Check for tone1 (G5 ~783 Hz)
        if abs(peakFrequency - Self.tone1Frequency) <= Self.frequencyTolerance {
            tone1DetectedAt = Date()
            return
        }

        // Check for tone2 (E5 ~659 Hz) following tone1
        if abs(peakFrequency - Self.tone2Frequency) <= Self.frequencyTolerance {
            if let tone1Time = tone1DetectedAt,
               Date().timeIntervalSince(tone1Time) <= Self.maxToneGap {
                // Chime detected!
                tone1DetectedAt = nil
                lastChimeAt = Date()
                onChimeDetected?()
            }
        }
    }
}
#endif
