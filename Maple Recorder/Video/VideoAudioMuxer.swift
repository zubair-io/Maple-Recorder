#if !os(watchOS)
import AVFoundation
import Foundation

/// Joins the separately-captured mic audio (.m4a chunks) into the camera-only
/// .mov so the saved video plays with sound. Capture itself stays video-only
/// by design — the microphone belongs solely to AudioRecorder, so the two
/// hardware pipelines never contend — and this merges the finished files
/// afterward instead. Passthrough export: no re-encoding, so it completes in
/// seconds even for long recordings.
enum VideoAudioMuxer {
    enum MuxError: Error {
        case missingVideoTrack
        case exportSessionUnavailable
    }

    /// - Parameter audioLeadIn: how much earlier the audio file's timeline
    ///   starts than the video's (seconds). That much audio is skipped so the
    ///   two tracks align; audio chunks are laid down back-to-back after that.
    static func muxedVideo(videoURL: URL, audioURLs: [URL], audioLeadIn: TimeInterval) async throws -> URL {
        let composition = AVMutableComposition()

        let videoAsset = AVURLAsset(url: videoURL)
        guard let sourceVideoTrack = try await videoAsset.loadTracks(withMediaType: .video).first,
              let videoTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
        else {
            throw MuxError.missingVideoTrack
        }
        let videoDuration = try await videoAsset.load(.duration)
        try videoTrack.insertTimeRange(CMTimeRange(start: .zero, duration: videoDuration), of: sourceVideoTrack, at: .zero)
        // Without this the iPhone's portrait rotation metadata is lost and the
        // muxed video plays sideways.
        videoTrack.preferredTransform = try await sourceVideoTrack.load(.preferredTransform)

        if let audioTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) {
            var cursor = CMTime.zero
            var leadIn = CMTime(seconds: max(0, audioLeadIn), preferredTimescale: 600)
            for url in audioURLs {
                let asset = AVURLAsset(url: url)
                guard let sourceAudioTrack = try await asset.loadTracks(withMediaType: .audio).first else { continue }
                let duration = try await asset.load(.duration)
                var start = CMTime.zero
                if leadIn > .zero {
                    if leadIn >= duration {
                        // Entire chunk falls before the video started
                        leadIn = leadIn - duration
                        continue
                    }
                    start = leadIn
                    leadIn = .zero
                }
                try audioTrack.insertTimeRange(CMTimeRange(start: start, end: duration), of: sourceAudioTrack, at: cursor)
                cursor = cursor + (duration - start)
            }
        }

        guard let export = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetPassthrough) else {
            throw MuxError.exportSessionUnavailable
        }
        let outURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("muxed-\(videoURL.lastPathComponent)")
        try? FileManager.default.removeItem(at: outURL)
        try await export.export(to: outURL, as: .mov)
        return outURL
    }
}
#endif
