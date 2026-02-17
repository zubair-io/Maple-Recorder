#if os(watchOS)
import AVFoundation
import Combine
import SwiftUI

struct WatchRecordingView: View {
    @Bindable var store: RecordingStore
    @State private var recorder = WatchAudioRecorder()
    @State private var transferManager = WatchTransferManager()
    @State private var showList = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if recorder.isRecording {
                    recordingView
                } else {
                    idleView
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black)
            .navigationTitle("")
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showList) {
                recordingsList
            }
        }
        .tint(MapleTheme.primary)
    }

    // MARK: - Idle State

    private var idleView: some View {
        VStack(spacing: 16) {
            Spacer()

            // Record button
            Button {
                startRecording()
            } label: {
                Circle()
                    .fill(MapleTheme.primary)
                    .frame(width: 80, height: 80)
                    .overlay {
                        Image(systemName: "mic.fill")
                            .font(.system(size: 30, weight: .medium))
                            .foregroundStyle(.white)
                    }
            }
            .buttonStyle(.plain)

            Text("Tap to Record")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

            // Recordings list button
            if !store.recordings.isEmpty {
                Button {
                    showList = true
                } label: {
                    Label("\(store.recordings.count) Recordings", systemImage: "list.bullet")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .padding(.bottom, 4)
            }

            // Transfer status
            if transferManager.isTransferring {
                HStack(spacing: 6) {
                    ProgressView(value: transferManager.transferProgress)
                        .tint(MapleTheme.primary)
                        .frame(width: 60)
                    Text("Sending…")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                .padding(.bottom, 4)
            }
        }
    }

    // MARK: - Recording State

    private var recordingView: some View {
        VStack(spacing: 12) {
            Spacer()

            // Stop button with pulsing waveform behind it
            ZStack {
                PulsingWaveform(audioLevel: recorder.audioLevel)

                Button {
                    stopRecording()
                } label: {
                    Circle()
                        .fill(.red)
                        .frame(width: 56, height: 56)
                        .overlay {
                            RoundedRectangle(cornerRadius: 6)
                                .fill(.white)
                                .frame(width: 22, height: 22)
                        }
                }
                .buttonStyle(.plain)
            }

            // Elapsed time
            Text(formatTime(recorder.elapsedTime))
                .font(.system(.title3, design: .monospaced))
                .foregroundStyle(.white)

            Text("Recording")
                .font(.caption2)
                .foregroundStyle(.red)
                .textCase(.uppercase)
                .tracking(1)

            Spacer()
        }
    }

    // MARK: - Recordings List

    private var recordingsList: some View {
        NavigationStack {
            List {
                ForEach(store.recordings) { recording in
                    NavigationLink(value: recording.id) {
                        WatchRecordingRow(recording: recording)
                    }
                }
            }
            .navigationTitle("Recordings")
            .navigationDestination(for: UUID.self) { id in
                WatchDetailView(store: store, recordingId: id)
            }
        }
    }

    // MARK: - Actions

    private func startRecording() {
        do {
            _ = try recorder.startRecording()
        } catch {
            print("Watch recording failed: \(error)")
        }
    }

    private func stopRecording() {
        guard let url = recorder.stopRecording() else { return }

        let now = Date()
        let title = "Watch \(now.formatted(date: .abbreviated, time: .shortened))"
        let fileName = url.lastPathComponent

        let destURL = StorageLocation.recordingsURL.appendingPathComponent(fileName)
        try? FileManager.default.copyItem(at: url, to: destURL)

        let recording = MapleRecording(
            title: title,
            audioFiles: [fileName],
            createdAt: now,
            modifiedAt: now
        )
        try? store.save(recording)

        // Only transfer via WatchConnectivity if iCloud is unavailable
        if FileManager.default.url(forUbiquityContainerIdentifier: "iCloud.com.just.maple.Maple-Recorder") == nil {
            transferManager.transferRecording(
                fileURL: url,
                metadata: [
                    "title": title,
                    "recordingId": recording.id.uuidString,
                ]
            )
        }
    }

    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

// MARK: - Row

private struct WatchRecordingRow: View {
    let recording: MapleRecording

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(recording.title)
                .font(.headline)
                .lineLimit(1)

            Text(recording.createdAt, style: .date)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Detail

struct WatchDetailView: View {
    @Bindable var store: RecordingStore
    let recordingId: UUID
    @State private var player = AudioPlayer()
    @State private var isDownloadingAudio = false
    @State private var audioReady = false

    private var recording: MapleRecording? {
        store.recordings.first { $0.id == recordingId }
    }

    var body: some View {
        if let recording {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text(recording.title)
                        .font(.headline)

                    // Playback controls
                    if !recording.audioFiles.isEmpty {
                        playbackSection(recording: recording)
                    }

                    if !recording.summary.isEmpty {
                        Text(recording.summary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if !recording.transcript.isEmpty {
                        Divider()
                        ForEach(recording.transcript) { segment in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(speakerName(for: segment, in: recording))
                                    .font(.caption2)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(MapleTheme.primary)
                                Text(segment.text)
                                    .font(.caption)
                            }
                            .padding(.vertical, 2)
                        }
                    } else {
                        Text("Transcript will appear after processing.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .italic()
                    }
                }
                .padding(.horizontal)
            }
            .navigationTitle(recording.title)
        } else {
            Text("Not found")
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Playback

    @ViewBuilder
    private func playbackSection(recording: MapleRecording) -> some View {
        VStack(spacing: 8) {
            if isDownloadingAudio {
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Downloading…")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            } else if audioReady {
                // Time display
                Text(formatPlaybackTime(player.currentTime, duration: player.duration))
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.secondary)

                // Transport controls
                HStack(spacing: 16) {
                    Button { player.skipBack(15) } label: {
                        Image(systemName: "gobackward.15")
                            .font(.title3)
                    }
                    .buttonStyle(.plain)

                    Button { player.togglePlayPause() } label: {
                        Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .font(.system(size: 36))
                            .foregroundStyle(MapleTheme.primary)
                    }
                    .buttonStyle(.plain)

                    Button { player.skipForward(15) } label: {
                        Image(systemName: "goforward.15")
                            .font(.title3)
                    }
                    .buttonStyle(.plain)
                }
            } else {
                Button {
                    Task { await loadAudio(recording: recording) }
                } label: {
                    Label("Play", systemImage: "play.fill")
                        .font(.caption)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    private func loadAudio(recording: MapleRecording) async {
        isDownloadingAudio = true
        defer { isDownloadingAudio = false }

        let urls = recording.audioFiles.map {
            StorageLocation.recordingsURL.appendingPathComponent($0)
        }

        // Download from iCloud if needed
        do {
            try await ICloudFileDownloader.ensureAllDownloaded(urls: urls)
        } catch {
            print("Watch playback: Failed to download audio: \(error)")
            return
        }

        // Configure audio session for playback
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback)
            try session.setActive(true)
        } catch {
            print("Watch playback: Audio session setup failed: \(error)")
        }

        // Load into player
        do {
            if urls.count == 1 {
                try player.load(url: urls[0])
            } else {
                try player.loadChunks(urls: urls)
            }
            audioReady = true
        } catch {
            print("Watch playback: Failed to load audio: \(error)")
        }
    }

    private func formatPlaybackTime(_ current: TimeInterval, duration: TimeInterval) -> String {
        let cur = Int(current)
        let dur = Int(duration)
        return String(format: "%d:%02d / %d:%02d", cur / 60, cur % 60, dur / 60, dur % 60)
    }

    private func speakerName(for segment: TranscriptSegment, in recording: MapleRecording) -> String {
        recording.speakers.first { $0.id == segment.speakerId }?.displayName ?? segment.speakerId
    }
}
#endif
