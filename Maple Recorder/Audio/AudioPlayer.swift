import AVFoundation
import Foundation
import Observation

@Observable
final class AudioPlayer: NSObject, AVAudioPlayerDelegate, @unchecked Sendable {
    var isPlaying = false
    var currentTime: TimeInterval = 0
    var duration: TimeInterval = 0
    var playbackRate: Float = 1.0

    private var player: AVAudioPlayer?
    private var timer: Timer?

    func load(url: URL) throws {
        let audioPlayer = try AVAudioPlayer(contentsOf: url)
        audioPlayer.delegate = self
        audioPlayer.enableRate = true
        audioPlayer.prepareToPlay()
        self.player = audioPlayer
        self.duration = audioPlayer.duration
        self.currentTime = 0
    }

    func play() {
        player?.rate = playbackRate
        player?.play()
        isPlaying = true
        startTimeUpdates()
    }

    func pause() {
        player?.pause()
        isPlaying = false
        stopTimeUpdates()
    }

    func togglePlayPause() {
        if isPlaying {
            pause()
        } else {
            play()
        }
    }

    func seek(to time: TimeInterval) {
        player?.currentTime = time
        currentTime = time
    }

    func skipForward(_ seconds: TimeInterval = 15) {
        let target = min((player?.currentTime ?? 0) + seconds, duration)
        seek(to: target)
    }

    func skipBack(_ seconds: TimeInterval = 15) {
        let target = max((player?.currentTime ?? 0) - seconds, 0)
        seek(to: target)
    }

    func setRate(_ rate: Float) {
        playbackRate = rate
        if isPlaying {
            player?.rate = rate
        }
    }

    // MARK: - AVAudioPlayerDelegate

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            self.isPlaying = false
            self.currentTime = self.duration
            self.stopTimeUpdates()
        }
    }

    // MARK: - Private

    private func startTimeUpdates() {
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, let player = self.player else { return }
                self.currentTime = player.currentTime
            }
        }
    }

    private func stopTimeUpdates() {
        timer?.invalidate()
        timer = nil
    }
}
