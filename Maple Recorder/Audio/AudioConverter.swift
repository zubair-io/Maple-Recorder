#if !os(watchOS)
import FluidAudio
import Foundation

enum MapleAudioConverter {
    static func loadAndResample(url: URL) throws -> [Float] {
        let converter = AudioConverter()
        return try converter.resampleAudioFile(url)
    }
}
#endif
