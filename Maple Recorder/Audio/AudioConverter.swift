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
}
#endif
