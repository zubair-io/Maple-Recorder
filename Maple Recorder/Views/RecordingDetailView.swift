import SwiftUI

struct RecordingDetailView: View {
    let recording: MapleRecording
    @State private var player = AudioPlayer()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Title
                Text(recording.title)
                    .font(.system(.largeTitle, design: .rounded, weight: .bold))
                    .foregroundStyle(MapleTheme.textPrimary)

                // Metadata
                HStack(spacing: 16) {
                    Label(formatDuration(recording.duration), systemImage: "clock")
                    Label(recording.createdAt.formatted(date: .abbreviated, time: .shortened), systemImage: "calendar")
                }
                .font(.subheadline)
                .foregroundStyle(MapleTheme.textSecondary)

                // Playback controls
                if let audioFile = recording.audioFiles.first {
                    playbackSection(audioFile: audioFile)
                }

                Divider()
                    .foregroundStyle(MapleTheme.border)

                // Summary
                if !recording.summary.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Summary")
                            .font(.system(.title2, design: .rounded, weight: .semibold))
                            .foregroundStyle(MapleTheme.textPrimary)
                        Text(recording.summary)
                            .font(.body)
                            .foregroundStyle(MapleTheme.textPrimary)
                    }
                }

                // Transcript placeholder
                VStack(alignment: .leading, spacing: 8) {
                    Text("Transcript")
                        .font(.system(.title2, design: .rounded, weight: .semibold))
                        .foregroundStyle(MapleTheme.textPrimary)

                    if recording.transcript.isEmpty {
                        Text("Transcript will appear here after processing.")
                            .font(.body)
                            .foregroundStyle(MapleTheme.textSecondary)
                            .italic()
                    } else {
                        ForEach(recording.transcript) { segment in
                            HStack(alignment: .top, spacing: 8) {
                                Text(formatTimestamp(segment.start))
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundStyle(MapleTheme.textSecondary)
                                    .frame(width: 50, alignment: .trailing)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(segment.speakerId)
                                        .font(.caption)
                                        .fontWeight(.semibold)
                                        .foregroundStyle(MapleTheme.primary)
                                    Text(segment.text)
                                        .font(.body)
                                        .foregroundStyle(MapleTheme.textPrimary)
                                }
                            }
                        }
                    }
                }
            }
            .padding()
        }
        .background(MapleTheme.background)
        .navigationTitle(recording.title)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    // MARK: - Playback

    @ViewBuilder
    private func playbackSection(audioFile: String) -> some View {
        VStack(spacing: 12) {
            // Progress bar
            if player.duration > 0 {
                VStack(spacing: 4) {
                    ProgressView(value: player.currentTime, total: player.duration)
                        .tint(MapleTheme.primary)

                    HStack {
                        Text(formatDuration(player.currentTime))
                        Spacer()
                        Text(formatDuration(player.duration))
                    }
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(MapleTheme.textSecondary)
                }
            }

            // Controls
            HStack(spacing: 24) {
                Button { player.skipBack() } label: {
                    Image(systemName: "gobackward.15")
                        .font(.title2)
                }

                Button { player.togglePlayPause() } label: {
                    Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 44))
                }

                Button { player.skipForward() } label: {
                    Image(systemName: "goforward.15")
                        .font(.title2)
                }
            }
            .foregroundStyle(MapleTheme.primary)
        }
        .padding()
        .background(MapleTheme.surfaceAlt, in: .rect(cornerRadius: 12))
        .onAppear {
            let url = StorageLocation.recordingsURL.appendingPathComponent(audioFile)
            try? player.load(url: url)
        }
    }

    // MARK: - Helpers

    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    private func formatTimestamp(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
