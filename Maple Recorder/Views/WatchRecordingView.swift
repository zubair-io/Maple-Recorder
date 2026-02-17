#if os(watchOS)
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

            // Stop button with pulsing rings behind it
            ZStack {
                // Animated rings
                PulsingRings(audioLevel: recorder.audioLevel)

                // Stop button
                Button {
                    stopRecording()
                } label: {
                    Circle()
                        .fill(.red)
                        .frame(width: 80, height: 80)
                        .overlay {
                            RoundedRectangle(cornerRadius: 6)
                                .fill(.white)
                                .frame(width: 28, height: 28)
                        }
                }
                .buttonStyle(.plain)
            }
            .frame(width: 140, height: 140)

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

// MARK: - Pulsing Rings

private struct PulsingRings: View {
    let audioLevel: Float

    @State private var phase: Double = 0

    private let timer = Timer.publish(every: 1.0 / 30, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            ForEach(0..<3, id: \.self) { ring in
                Circle()
                    .stroke(
                        MapleTheme.primary.opacity(ringOpacity(ring: ring)),
                        lineWidth: 2
                    )
                    .frame(
                        width: ringSize(ring: ring),
                        height: ringSize(ring: ring)
                    )
                    .scaleEffect(ringScale(ring: ring))
            }
        }
        .onReceive(timer) { _ in
            phase += 0.05
        }
    }

    private func ringSize(ring: Int) -> CGFloat {
        let base: CGFloat = 90
        let spacing: CGFloat = 16
        return base + CGFloat(ring) * spacing
    }

    private func ringScale(ring: Int) -> CGFloat {
        let level = CGFloat(min(max(audioLevel, 0), 1))
        let offset = Double(ring) * 0.7
        let pulse = sin(phase + offset) * 0.5 + 0.5
        return 1.0 + level * 0.15 * pulse
    }

    private func ringOpacity(ring: Int) -> Double {
        let level = Double(min(max(audioLevel, 0), 1))
        let base = 0.15 + level * 0.5
        let offset = Double(ring) * 0.7
        let pulse = sin(phase + offset) * 0.5 + 0.5
        return base * (1.0 - Double(ring) * 0.25) * (0.6 + 0.4 * pulse)
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
