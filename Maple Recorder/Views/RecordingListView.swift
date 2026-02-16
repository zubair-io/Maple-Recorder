import SwiftUI

struct RecordingListView: View {
    @Bindable var store: RecordingStore
    @State private var recorder = AudioRecorder()
    @State private var recordingURL: URL?
    @State private var selectedRecording: MapleRecording?

    var body: some View {
        NavigationSplitView {
            List(store.recordings, selection: $selectedRecording) { recording in
                NavigationLink(value: recording) {
                    RecordingRow(recording: recording)
                }
            }
            .navigationTitle("Recordings")
            .overlay {
                if store.recordings.isEmpty && !recorder.isRecording {
                    ContentUnavailableView(
                        "No Recordings",
                        systemImage: "waveform",
                        description: Text("Tap the record button to start")
                    )
                }
            }
            .safeAreaInset(edge: .bottom) {
                recordButton
                    .padding()
            }
        } detail: {
            if let selectedRecording {
                RecordingDetailView(recording: selectedRecording)
            } else {
                ContentUnavailableView(
                    "Select a Recording",
                    systemImage: "waveform",
                    description: Text("Choose a recording from the list")
                )
            }
        }
        .tint(MapleTheme.primary)
    }

    // MARK: - Record Button

    @ViewBuilder
    private var recordButton: some View {
        if recorder.isRecording {
            VStack(spacing: 8) {
                Text(formatTime(recorder.elapsedTime))
                    .font(.system(.title3, design: .monospaced))
                    .foregroundStyle(MapleTheme.textPrimary)

                Button {
                    stopRecording()
                } label: {
                    Label("Stop", systemImage: "stop.fill")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(MapleTheme.error, in: .capsule)
                }
            }
        } else {
            Button {
                startRecording()
            } label: {
                Label("Record", systemImage: "mic.fill")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(MapleTheme.primary, in: .capsule)
            }
        }
    }

    // MARK: - Actions

    private func startRecording() {
        Task {
            do {
                recordingURL = try await recorder.startRecording()
            } catch {
                print("Failed to start recording: \(error)")
            }
        }
    }

    private func stopRecording() {
        guard let url = recorder.stopRecording() else { return }

        let now = Date()
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        let title = "Recording \(formatter.string(from: now))"

        let audioFileName = url.lastPathComponent

        // Copy audio file to recordings directory
        let destURL = StorageLocation.recordingsURL.appendingPathComponent(audioFileName)
        try? FileManager.default.copyItem(at: url, to: destURL)

        let recording = MapleRecording(
            title: title,
            audioFiles: [audioFileName],
            createdAt: now,
            modifiedAt: now
        )

        do {
            try store.save(recording)
            selectedRecording = recording
        } catch {
            print("Failed to save recording: \(error)")
        }
    }

    // MARK: - Helpers

    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

// MARK: - Row

private struct RecordingRow: View {
    let recording: MapleRecording

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(recording.title)
                .font(.headline)
                .foregroundStyle(MapleTheme.textPrimary)

            HStack {
                Text(formatDuration(recording.duration))
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(MapleTheme.textSecondary)

                Text("·")
                    .foregroundStyle(MapleTheme.textSecondary)

                Text(recording.createdAt, style: .date)
                    .font(.caption)
                    .foregroundStyle(MapleTheme.textSecondary)
            }

            if !recording.summary.isEmpty {
                Text(recording.summary)
                    .font(.subheadline)
                    .foregroundStyle(MapleTheme.textSecondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 4)
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

extension MapleRecording: Hashable {
    static func == (lhs: MapleRecording, rhs: MapleRecording) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
