import Foundation
import Observation

/// Common transport interface for the playback bar and transcript sync engine.
/// Implemented by AudioPlayer (chunked m4a playback) and
/// VideoPlaybackController (AVPlayer-backed video playback), so a recording
/// with video drives the same play/seek/speed UI through its video file.
protocol PlaybackTransport: AnyObject, Observable {
    var isPlaying: Bool { get }
    var currentTime: TimeInterval { get }
    var duration: TimeInterval { get }
    var speed: PlaybackSpeed { get }

    func togglePlayPause()
    func pause()
    func seek(to time: TimeInterval)
    func skipForward(_ seconds: TimeInterval)
    func skipBack(_ seconds: TimeInterval)
    func cycleSpeed()
}

extension AudioPlayer: PlaybackTransport {}
