import SwiftUI

struct RecordingDetailView: View {
    @Bindable var store: RecordingStore
    let recordingId: UUID
    @State private var player = AudioPlayer()
    @State private var syncEngine = PlaybackSyncEngine()
    @State private var editingSpeaker: Speaker?

    #if !os(watchOS)
    var processingPipeline: ProcessingPipeline?
    var settingsManager: SettingsManager?
    var promptStore: PromptStore?
    @State private var showingPromptPicker = false
    @State private var isRunningPrompt = false
    #endif

    private var recording: MapleRecording? {
        store.recordings.first { $0.id == recordingId }
    }

    var body: some View {
        if var recording = recording {
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
                    if !recording.audioFiles.isEmpty {
                        playbackSection(audioFiles: recording.audioFiles, transcript: recording.transcript)
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

                    // Transcript section
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Transcript")
                            .font(.system(.title2, design: .rounded, weight: .semibold))
                            .foregroundStyle(MapleTheme.textPrimary)

                        #if !os(watchOS)
                        if recording.transcript.isEmpty, let pipeline = processingPipeline {
                            processingIndicator(pipeline: pipeline)
                        } else if recording.transcript.isEmpty {
                            emptyTranscriptPlaceholder
                        } else {
                            TranscriptView(
                                transcript: recording.transcript,
                                speakers: recording.speakers,
                                syncEngine: syncEngine,
                                onSeekToWord: { word in
                                    player.seek(to: word.start)
                                },
                                onRenameSpeaker: { speaker in
                                    editingSpeaker = speaker
                                }
                            )
                        }
                        #else
                        emptyTranscriptPlaceholder
                        #endif
                    }

                    #if !os(watchOS)
                    // Prompt Results
                    PromptResultsView(
                        results: recording.promptResults,
                        onDelete: { result in
                            deletePromptResult(result, from: &recording)
                        }
                    )

                    // Run Prompt button
                    if !recording.transcript.isEmpty, promptStore != nil, settingsManager != nil {
                        runPromptButton
                    }
                    #endif
                }
                .padding()
            }
            .background(MapleTheme.background)
            .navigationTitle(recording.title)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .speakerEditor(
                recording: Binding(
                    get: { recording },
                    set: { recording = $0 }
                ),
                editingSpeaker: $editingSpeaker,
                onSave: { updated in
                    try? store.update(updated)
                }
            )
            #if !os(watchOS)
            .sheet(isPresented: $showingPromptPicker) {
                if let promptStore, let settingsManager {
                    PromptPickerView(
                        prompts: promptStore.prompts,
                        provider: settingsManager.preferredProvider
                    ) { prompt, context in
                        Task {
                            await runPrompt(prompt, context: context, on: recording)
                        }
                    }
                }
            }
            #endif
        } else {
            ContentUnavailableView(
                "Recording Not Found",
                systemImage: "waveform",
                description: Text("This recording may have been deleted.")
            )
        }
    }

    // MARK: - Subviews

    private var emptyTranscriptPlaceholder: some View {
        Text("Transcript will appear here after processing.")
            .font(.body)
            .foregroundStyle(MapleTheme.textSecondary)
            .italic()
    }

    #if !os(watchOS)
    @ViewBuilder
    private func processingIndicator(pipeline: ProcessingPipeline) -> some View {
        VStack(spacing: 8) {
            ProgressView()
                .controlSize(.regular)
            Text(pipeline.progress)
                .font(.subheadline)
                .foregroundStyle(MapleTheme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.vertical, 20)
    }

    @ViewBuilder
    private var runPromptButton: some View {
        Button {
            showingPromptPicker = true
        } label: {
            HStack {
                if isRunningPrompt {
                    ProgressView()
                        .controlSize(.small)
                    Text("Running prompt…")
                } else {
                    Image(systemName: "sparkles")
                    Text("Run Custom Prompt…")
                }
            }
            .font(.headline)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                isRunningPrompt ? MapleTheme.textSecondary : MapleTheme.primary,
                in: .capsule
            )
        }
        .disabled(isRunningPrompt)
    }

    private func runPrompt(_ prompt: CustomPrompt, context: String?, on recording: MapleRecording) async {
        guard let settingsManager else { return }
        isRunningPrompt = true
        defer { isRunningPrompt = false }

        do {
            let result = try await PromptRunner.execute(
                prompt: prompt,
                additionalContext: context,
                transcript: recording.transcript,
                speakers: recording.speakers,
                provider: settingsManager.preferredProvider
            )
            var updated = recording
            updated.promptResults.append(result)
            try store.update(updated)
        } catch {
            print("Prompt execution failed: \(error)")
        }
    }

    private func deletePromptResult(_ result: PromptResult, from recording: inout MapleRecording) {
        recording.promptResults.removeAll { $0.id == result.id }
        try? store.update(recording)
    }
    #endif

    // MARK: - Playback

    @ViewBuilder
    private func playbackSection(audioFiles: [String], transcript: [TranscriptSegment]) -> some View {
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

                Button {
                    player.togglePlayPause()
                    if player.isPlaying {
                        syncEngine.start(player: player, transcript: transcript)
                    } else {
                        syncEngine.stop()
                    }
                } label: {
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
            let urls = audioFiles.map { StorageLocation.recordingsURL.appendingPathComponent($0) }
            if urls.count == 1 {
                try? player.load(url: urls[0])
            } else {
                try? player.loadChunks(urls: urls)
            }
        }
    }

    // MARK: - Helpers

    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
