#if os(macOS)
import Accelerate
import AVFoundation
import Foundation

/// Detects the Google Meet end-call chime in system audio.
///
/// The chime is a two-tone descending pattern: a higher tone followed by a lower tone
/// within ~0.6 seconds. Rather than relying on a single dominant-frequency check
/// (which fails when people are talking), this detector looks for a *significant peak*
/// near each target frequency that stands out above the local spectral noise floor.
///
/// Uses 50%-overlapping FFT frames for better temporal resolution and Accelerate
/// vDSP on a dedicated queue to avoid blocking audio writes.
///
/// **Calibration:** The default frequencies (~880 Hz → ~698 Hz) are approximate.
/// For best results, record the actual Google Meet end-call chime, inspect its
/// spectrogram, and update `tone1Frequency` / `tone2Frequency`.
final class EndCallChimeDetector: @unchecked Sendable {
    var onChimeDetected: (() -> Void)?

    // FFT parameters: 4096-point at 48 kHz → ~11.7 Hz bin resolution, ~85 ms per frame
    private let fftSize = 4096
    private let hopSize: Int  // 50% overlap = fftSize / 2
    private let sampleRate: Double = 48000.0
    private let analysisQueue = DispatchQueue(label: "com.maple.chimeDetector", qos: .utility)

    // Frequency targets (Hz) — approximate Google Meet end-call chime
    // These should be calibrated from a real recording of the chime.
    private static let tone1Frequency: Double = 880.0   // Higher tone (A5)
    private static let tone2Frequency: Double = 698.0   // Lower tone (F5)
    private static let frequencyTolerance: Double = 35.0 // ±35 Hz search band

    // Timing: tone2 must follow tone1 within this window
    private static let maxToneGap: TimeInterval = 0.6

    // Cooldown to prevent re-triggers on the same chime
    private static let cooldownDuration: TimeInterval = 10.0

    // Peak detection: the target-band peak must be this many times above
    // the median magnitude in the 200–2000 Hz range (signal-to-noise ratio)
    private static let snrThreshold: Float = 8.0

    // Minimum absolute magnitude to reject silence
    private static let minMagnitude: Float = 0.005

    // Ring buffer to accumulate small SCStream buffers
    private var ringBuffer: [Float] = []

    // Detection state
    private var tone1DetectedAt: Date?
    private var lastChimeAt: Date?

    // Precomputed Hann window (reused every frame)
    private let hannWindow: [Float]

    // vDSP FFT setup (created once, reused)
    private let fftSetup: FFTSetup?
    private let log2n: vDSP_Length

    init() {
        let size = 4096
        hopSize = size / 2
        log2n = vDSP_Length(log2(Double(size)))
        fftSetup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2))

        // Precompute Hann window
        var window = [Float](repeating: 0, count: size)
        vDSP_hann_window(&window, vDSP_Length(size), Int32(vDSP_HANN_NORM))
        hannWindow = window

        ringBuffer.reserveCapacity(size * 3)
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

    /// Clear internal state (call after a stream disconnection/reconnection).
    func reset() {
        analysisQueue.async { [weak self] in
            self?.ringBuffer.removeAll(keepingCapacity: true)
            self?.tone1DetectedAt = nil
        }
    }

    // MARK: - Private

    private func accumulateAndAnalyze(_ samples: [Float]) {
        ringBuffer.append(contentsOf: samples)

        // Process with 50% overlap: advance by hopSize each iteration
        while ringBuffer.count >= fftSize {
            let frame = Array(ringBuffer.prefix(fftSize))
            ringBuffer.removeFirst(hopSize)
            analyzeFrame(frame)
        }

        // Prevent unbounded growth
        if ringBuffer.count > fftSize * 3 {
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

        // Apply precomputed Hann window
        var windowed = [Float](repeating: 0, count: fftSize)
        vDSP_vmul(frame, 1, hannWindow, 1, &windowed, 1, vDSP_Length(fftSize))

        // FFT → magnitude spectrum
        let halfSize = fftSize / 2
        var realPart = [Float](repeating: 0, count: halfSize)
        var imagPart = [Float](repeating: 0, count: halfSize)

        realPart.withUnsafeMutableBufferPointer { realBuf in
            imagPart.withUnsafeMutableBufferPointer { imagBuf in
                var splitComplex = DSPSplitComplex(
                    realp: realBuf.baseAddress!,
                    imagp: imagBuf.baseAddress!
                )

                windowed.withUnsafeBufferPointer { windowedBuf in
                    windowedBuf.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: halfSize) { complexPtr in
                        vDSP_ctoz(complexPtr, 2, &splitComplex, 1, vDSP_Length(halfSize))
                    }
                }

                vDSP_fft_zrip(fftSetup, &splitComplex, 1, log2n, FFTDirection(kFFTDirection_Forward))

                var magnitudes = [Float](repeating: 0, count: halfSize)
                vDSP_zvmags(&splitComplex, 1, &magnitudes, 1, vDSP_Length(halfSize))

                // Use square-root magnitudes for more intuitive thresholds
                var sqrtMags = [Float](repeating: 0, count: halfSize)
                var count = Int32(halfSize)
                vvsqrtf(&sqrtMags, magnitudes, &count)

                checkTones(magnitudes: sqrtMags)
            }
        }
    }

    private func checkTones(magnitudes: [Float]) {
        let binResolution = sampleRate / Double(fftSize)

        // Analysis range: 200 Hz – 2000 Hz
        let minBin = max(1, Int(200.0 / binResolution))
        let maxBin = min(magnitudes.count - 1, Int(2000.0 / binResolution))
        guard minBin < maxBin else { return }

        // Compute median magnitude in analysis range for SNR baseline
        let rangeSlice = Array(magnitudes[minBin...maxBin])
        let medianMag = median(rangeSlice)

        // Check both tones in this frame
        let tone1Detected = isTonePresent(
            frequency: Self.tone1Frequency,
            tolerance: Self.frequencyTolerance,
            magnitudes: magnitudes,
            binResolution: binResolution,
            medianMag: medianMag
        )
        let tone2Detected = isTonePresent(
            frequency: Self.tone2Frequency,
            tolerance: Self.frequencyTolerance,
            magnitudes: magnitudes,
            binResolution: binResolution,
            medianMag: medianMag
        )

        if tone1Detected {
            // Record tone1 time (don't return — also check tone2)
            if tone1DetectedAt == nil {
                tone1DetectedAt = Date()
            }
        }

        if tone2Detected {
            if let tone1Time = tone1DetectedAt,
               Date().timeIntervalSince(tone1Time) <= Self.maxToneGap {
                // Both tones detected in sequence — chime matched
                tone1DetectedAt = nil
                lastChimeAt = Date()
                onChimeDetected?()
                return
            }
        }

        // Expire stale tone1 detections
        if let tone1Time = tone1DetectedAt,
           Date().timeIntervalSince(tone1Time) > Self.maxToneGap * 2 {
            tone1DetectedAt = nil
        }
    }

    /// Check if there is a significant peak near `frequency` that stands above the noise floor.
    private func isTonePresent(
        frequency: Double,
        tolerance: Double,
        magnitudes: [Float],
        binResolution: Double,
        medianMag: Float
    ) -> Bool {
        let centerBin = Int(frequency / binResolution)
        let toleranceBins = Int(tolerance / binResolution)
        let lowBin = max(0, centerBin - toleranceBins)
        let highBin = min(magnitudes.count - 1, centerBin + toleranceBins)
        guard lowBin <= highBin else { return false }

        // Find peak in the target band
        var peakMag: Float = 0
        for bin in lowBin...highBin {
            peakMag = max(peakMag, magnitudes[bin])
        }

        // Must exceed absolute minimum (reject silence)
        guard peakMag > Self.minMagnitude else { return false }

        // Must stand out above the spectral noise floor (SNR check)
        let snr = medianMag > 0 ? peakMag / medianMag : peakMag
        return snr >= Self.snrThreshold
    }

    private func median(_ values: [Float]) -> Float {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let mid = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[mid - 1] + sorted[mid]) / 2.0
        }
        return sorted[mid]
    }
}
#endif
