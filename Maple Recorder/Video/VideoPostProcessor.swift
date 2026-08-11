#if !os(watchOS)
import AVFoundation
import Foundation

/// Post-recording steps for camera captures. The session records audio+video
/// together (natively synced), then:
/// 1. the QuickTime capture output is remuxed into an .mp4 container
///    (passthrough — the session already encodes H.264 + AAC, no re-encode),
/// 2. the audio track is extracted to an .m4a that replaces the mic-recorded
///    file, so transcription runs on the exact timeline of the video and word
///    timestamps line up 1:1 with video playback.
enum VideoPostProcessor {
    enum PostProcessError: Error {
        case missingAudioTrack
        case exportSessionUnavailable
    }

    static func remuxToMP4(videoURL: URL) async throws -> URL {
        let asset = AVURLAsset(url: videoURL)
        guard let export = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetPassthrough) else {
            throw PostProcessError.exportSessionUnavailable
        }
        let outURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(videoURL.deletingPathExtension().lastPathComponent)-remux.mp4")
        try? FileManager.default.removeItem(at: outURL)
        try await export.export(to: outURL, as: .mp4)
        return outURL
    }

    static func extractAudioM4A(from videoURL: URL) async throws -> URL {
        let asset = AVURLAsset(url: videoURL)
        guard try await !asset.loadTracks(withMediaType: .audio).isEmpty else {
            throw PostProcessError.missingAudioTrack
        }
        guard let export = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            throw PostProcessError.exportSessionUnavailable
        }
        let outURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(videoURL.deletingPathExtension().lastPathComponent)-audio.m4a")
        try? FileManager.default.removeItem(at: outURL)
        try await export.export(to: outURL, as: .m4a)
        return outURL
    }
}
#endif
