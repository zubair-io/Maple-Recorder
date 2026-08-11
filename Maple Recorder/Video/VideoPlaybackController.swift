#if !os(watchOS)
import AVFoundation
import Foundation
import Observation

/// AVPlayer-backed playback transport for recordings that have a video file.
/// Drives the shared PlaybackBar/transcript-sync UI while the frames render in
/// the detail view's VideoPlayer (which observes the same `avPlayer`).
@Observable
final class VideoPlaybackController: PlaybackTransport {
    let avPlayer = AVPlayer()

    private(set) var isPlaying = false
    private(set) var currentTime: TimeInterval = 0
    private(set) var duration: TimeInterval = 0
    private(set) var speed: PlaybackSpeed = .x1

    private var timeObserver: Any?
    private var endObserver: (any NSObjectProtocol)?
    private var loadedURL: URL?

    func load(url: URL) async {
        guard loadedURL != url else { return }
        loadedURL = url
        removeObservers()

        let asset = AVURLAsset(url: url)
        let item = AVPlayerItem(asset: asset)
        avPlayer.replaceCurrentItem(with: item)
        duration = (try? await asset.load(.duration).seconds) ?? 0
        currentTime = 0
        isPlaying = false

        timeObserver = avPlayer.addPeriodicTimeObserver(
            forInterval: CMTime(value: 1, timescale: 30),
            queue: .main
        ) { [weak self] time in
            Task { @MainActor [weak self] in
                self?.currentTime = time.seconds
            }
        }
        endObserver = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.didPlayToEndTimeNotification,
            object: item,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.isPlaying = false
                self.currentTime = self.duration
            }
        }
    }

    func unload() {
        avPlayer.pause()
        removeObservers()
        avPlayer.replaceCurrentItem(with: nil)
        loadedURL = nil
        isPlaying = false
        currentTime = 0
        duration = 0
    }

    func play() {
        // Restart from the top when play is hit at the end
        if duration > 0, currentTime >= duration - 0.05 {
            avPlayer.seek(to: .zero)
            currentTime = 0
        }
        // Setting a non-zero rate both starts playback and applies the speed
        avPlayer.rate = speed.rawValue
        isPlaying = true
    }

    func pause() {
        avPlayer.pause()
        isPlaying = false
    }

    func togglePlayPause() {
        if isPlaying {
            pause()
        } else {
            play()
        }
    }

    func seek(to time: TimeInterval) {
        let clamped = max(0, min(time, duration))
        avPlayer.seek(
            to: CMTime(seconds: clamped, preferredTimescale: 600),
            toleranceBefore: .zero,
            toleranceAfter: .zero
        )
        currentTime = clamped
    }

    func skipForward(_ seconds: TimeInterval = 15) {
        seek(to: currentTime + seconds)
    }

    func skipBack(_ seconds: TimeInterval = 15) {
        seek(to: currentTime - seconds)
    }

    func cycleSpeed() {
        speed = speed.next()
        if isPlaying {
            avPlayer.rate = speed.rawValue
        }
    }

    private func removeObservers() {
        if let timeObserver {
            avPlayer.removeTimeObserver(timeObserver)
            self.timeObserver = nil
        }
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
            self.endObserver = nil
        }
    }
}
#endif
