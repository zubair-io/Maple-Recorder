#if os(watchOS)
import SwiftUI

struct WatchRecordingView: View {
    @Bindable var store: RecordingStore
    @State private var recorder = WatchAudioRecorder()
    @State private var transferManager = WatchTransferManager()
    @State private var selectedRecordingId: UUID?

    var body: some View {
        NavigationStack {
            List {
                // Recording controls at top
                Section {
                    recordButton
                }

                // Transfer status
                if transferManager.isTransferring {
                    Section {
                        HStack(spacing: 8) {
                            ProgressView(value: transferManager.transferProgress)
                                .tint(MapleTheme.primary)
                            Text("Sending…")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                // Recordings list
                Section {
                    ForEach(store.recordings) { recording in
                        NavigationLink(value: recording.id) {
                            WatchRecordingRow(recording: recording)
                        }
                    }
                }
            }
            .navigationTitle("Maple")
            .navigationDestination(for: UUID.self) { id in
                WatchDetailView(store: store, recordingId: id)
            }
        }
        .tint(MapleTheme.primary)
    }

    @ViewBuilder
    private var recordButton: some View {
        if recorder.isRecording {
            VStack(spacing: 6) {
                // Audio level indicator
                HStack(spacing: 2) {
                    ForEach(0..<5, id: \.self) { i in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Float(i) / 5.0 < recorder.audioLevel
                                  ? MapleTheme.primary
                                  : MapleTheme.primary.opacity(0.2))
                            .frame(width: 6, height: 12 + CGFloat(i) * 4)
                    }
                }
                .frame(height: 32)

                Text(formatTime(recorder.elapsedTime))
                    .font(.system(.body, design: .monospaced))

                Button {
                    stopRecording()
                } label: {
                    Label("Stop", systemImage: "stop.fill")
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
            }
        } else {
            Button {
                startRecording()
            } label: {
                Label("Record", systemImage: "mic.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(MapleTheme.primary)
        }
    }

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

        // Save locally
        let destURL = StorageLocation.recordingsURL.appendingPathComponent(fileName)
        try? FileManager.default.copyItem(at: url, to: destURL)

        let recording = MapleRecording(
            title: title,
            audioFiles: [fileName],
            createdAt: now,
            modifiedAt: now
        )
        try? store.save(recording)

        // Transfer to iPhone for processing
        transferManager.transferRecording(
            fileURL: url,
            metadata: [
                "title": title,
                "recordingId": recording.id.uuidString,
            ]
        )
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

    private var recording: MapleRecording? {
        store.recordings.first { $0.id == recordingId }
    }

    var body: some View {
        if let recording {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text(recording.title)
                        .font(.headline)

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
                        Text("Transcript will appear after iPhone processes this recording.")
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

    private func speakerName(for segment: TranscriptSegment, in recording: MapleRecording) -> String {
        recording.speakers.first { $0.id == segment.speakerId }?.displayName ?? segment.speakerId
    }
}
#endif
