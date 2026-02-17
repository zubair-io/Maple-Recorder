#if !os(watchOS)
import FluidAudio
import Foundation

enum MapleAudioConverter {
    static func loadAndResample(url: URL) throws -> [Float] {
        let converter = AudioConverter()
        return try converter.resampleAudioFile(url)
    }

    /// Concatenate and resample multiple audio chunk files into a single sample buffer
    static func loadAndResampleChunks(urls: [URL]) throws -> [Float] {
        let converter = AudioConverter()
        var allSamples: [Float] = []
        for url in urls {
            let samples = try converter.resampleAudioFile(url)
            allSamples.append(contentsOf: samples)
        }
        return allSamples
    }

    /// Mix two sample arrays by addition, clamped to [-1, 1].
    /// If lengths differ, the shorter one is zero-padded.
    static func mixSamples(_ a: [Float], _ b: [Float], levelA: Float = 1.0, levelB: Float = 0.7) -> [Float] {
        let count = max(a.count, b.count)
        var result = [Float](repeating: 0, count: count)
        for i in 0..<count {
            let va = i < a.count ? a[i] * levelA : 0
            let vb = i < b.count ? b[i] * levelB : 0
            result[i] = max(-1.0, min(1.0, va + vb))
        }
        return result
    }
}
#endif
