import AVFoundation
import Foundation
import Observation

@Observable
final class AudioPlayer: NSObject, AVAudioPlayerDelegate, @unchecked Sendable {
    var isPlaying = false
    var currentTime: TimeInterval = 0
    var duration: TimeInterval = 0
    var playbackRate: Float = 1.0

    private var players: [(player: AVAudioPlayer, startOffset: TimeInterval, fileDuration: TimeInterval)] = []
    private var currentChunkIndex = 0
    private var timer: Timer?
    private var preloadThreshold: TimeInterval = 5.0

    /// Load a single audio file
    func load(url: URL) throws {
        try loadChunks(urls: [url])
    }

    /// Load multiple chunks for seamless playback
    func loadChunks(urls: [URL]) throws {
        stopTimeUpdates()
        players = []
        var offset: TimeInterval = 0

        for url in urls {
            let audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer.delegate = self
            audioPlayer.enableRate = true
            audioPlayer.prepareToPlay()

            players.append((
                player: audioPlayer,
                startOffset: offset,
                fileDuration: audioPlayer.duration
            ))
            offset += audioPlayer.duration
        }

        self.duration = offset
        self.currentTime = 0
        self.currentChunkIndex = 0
    }

    func play() {
        guard !players.isEmpty else { return }
        let chunk = players[currentChunkIndex]
        chunk.player.rate = playbackRate
        chunk.player.play()
        isPlaying = true
        startTimeUpdates()
    }

    func pause() {
        for entry in players {
            entry.player.pause()
        }
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
        let clamped = max(0, min(time, duration))

        // Find the right chunk
        guard let index = chunkIndex(for: clamped) else { return }

        // Pause current chunk if different
        if index != currentChunkIndex {
            players[currentChunkIndex].player.pause()
        }

        currentChunkIndex = index
        let chunk = players[index]
        let localTime = clamped - chunk.startOffset
        chunk.player.currentTime = localTime
        currentTime = clamped

        if isPlaying {
            chunk.player.rate = playbackRate
            chunk.player.play()
        }
    }

    func skipForward(_ seconds: TimeInterval = 15) {
        seek(to: currentTime + seconds)
    }

    func skipBack(_ seconds: TimeInterval = 15) {
        seek(to: currentTime - seconds)
    }

    func setRate(_ rate: Float) {
        playbackRate = rate
        if isPlaying {
            players[currentChunkIndex].player.rate = rate
        }
    }

    // MARK: - AVAudioPlayerDelegate

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            self.handleChunkFinished()
        }
    }

    private func handleChunkFinished() {
        let nextIndex = currentChunkIndex + 1
        if nextIndex < players.count {
            // Move to next chunk
            currentChunkIndex = nextIndex
            let next = players[nextIndex]
            next.player.currentTime = 0
            next.player.rate = playbackRate
            next.player.play()
        } else {
            // All chunks finished
            isPlaying = false
            currentTime = duration
            stopTimeUpdates()
        }
    }

    // MARK: - Private

    private func chunkIndex(for time: TimeInterval) -> Int? {
        for (i, entry) in players.enumerated() {
            let chunkEnd = entry.startOffset + entry.fileDuration
            if time < chunkEnd || i == players.count - 1 {
                return i
            }
        }
        return players.isEmpty ? nil : 0
    }

    private func startTimeUpdates() {
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                guard currentChunkIndex < self.players.count else { return }
                let chunk = self.players[self.currentChunkIndex]
                self.currentTime = chunk.startOffset + chunk.player.currentTime

                // Pre-load next chunk check
                let timeLeftInChunk = chunk.fileDuration - chunk.player.currentTime
                if timeLeftInChunk < self.preloadThreshold,
                   self.currentChunkIndex + 1 < self.players.count {
                    self.players[self.currentChunkIndex + 1].player.prepareToPlay()
                }
            }
        }
    }

    private func stopTimeUpdates() {
        timer?.invalidate()
        timer = nil
    }
}
