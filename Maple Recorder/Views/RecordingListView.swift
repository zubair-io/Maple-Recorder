import SwiftUI

struct RecordingListView: View {
    @Bindable var store: RecordingStore
    #if !os(watchOS)
    var modelManager: ModelManager
    @Bindable var settingsManager: SettingsManager
    @Bindable var promptStore: PromptStore
    #endif
    @State private var recorder = AudioRecorder()
    @State private var recordingURL: URL?
    @State private var selectedRecordingId: UUID?
    #if !os(watchOS)
    @State private var activePipeline: ProcessingPipeline?
    @State private var processingRecordingId: UUID?
    @State private var showingSettings = false
    #endif

    var body: some View {
        NavigationSplitView {
            List(store.recordings, selection: $selectedRecordingId) { recording in
                NavigationLink(value: recording.id) {
                    RecordingRow(
                        recording: recording,
                        isProcessing: isProcessing(recording)
                    )
                }
            }
            .navigationTitle("Recordings")
            #if !os(watchOS)
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    Button {
                        showingSettings = true
                    } label: {
                        Image(systemName: "gear")
                    }
                }
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView(settingsManager: settingsManager, promptStore: promptStore)
            }
            #endif
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
                VStack(spacing: 8) {
                    #if !os(watchOS)
                    modelStatusBanner
                    #endif
                    recordButton
                }
                .padding()
            }
        } detail: {
            if let selectedRecordingId {
                #if !os(watchOS)
                RecordingDetailView(
                    store: store,
                    recordingId: selectedRecordingId,
                    processingPipeline: processingRecordingId == selectedRecordingId ? activePipeline : nil,
                    settingsManager: settingsManager,
                    promptStore: promptStore
                )
                #else
                RecordingDetailView(
                    store: store,
                    recordingId: selectedRecordingId
                )
                #endif
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

    // MARK: - Model Status

    #if !os(watchOS)
    @ViewBuilder
    private var modelStatusBanner: some View {
        if modelManager.isDownloading {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("Downloading models…")
                    .font(.caption)
                    .foregroundStyle(MapleTheme.textSecondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(MapleTheme.surfaceAlt, in: .rect(cornerRadius: 8))
        } else if let error = modelManager.error {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(MapleTheme.error)
                Text(error)
                    .font(.caption)
                    .foregroundStyle(MapleTheme.textSecondary)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(MapleTheme.surfaceAlt, in: .rect(cornerRadius: 8))
        }
    }
    #endif

    // MARK: - Record Button

    @ViewBuilder
    private var recordButton: some View {
        if recorder.isRecording {
            VStack(spacing: 8) {
                WaveformView(samples: recorder.amplitudeSamples)
                    .frame(height: 60)

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
            selectedRecordingId = recording.id
        } catch {
            print("Failed to save recording: \(error)")
        }

        #if !os(watchOS)
        // Kick off processing pipeline
        if modelManager.isReady {
            Task {
                await processRecording(recording)
            }
        }
        #endif
    }

    #if !os(watchOS)
    private func processRecording(_ recording: MapleRecording) async {
        let pipeline = modelManager.createPipeline()
        activePipeline = pipeline
        processingRecordingId = recording.id

        do {
            try await store.processRecording(
                recording,
                pipeline: pipeline,
                transcription: modelManager.transcriptionManager,
                diarization: modelManager.diarizationManager,
                summarizationProvider: settingsManager.preferredProvider
            )
        } catch {
            print("Processing failed: \(error)")
        }

        activePipeline = nil
        processingRecordingId = nil
    }

    private func isProcessing(_ recording: MapleRecording) -> Bool {
        processingRecordingId == recording.id
    }
    #else
    private func isProcessing(_ recording: MapleRecording) -> Bool {
        false
    }
    #endif

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
    let isProcessing: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(recording.title)
                    .font(.headline)
                    .foregroundStyle(MapleTheme.textPrimary)

                if isProcessing {
                    ProgressView()
                        .controlSize(.small)
                }
            }

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
