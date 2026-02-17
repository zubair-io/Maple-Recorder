import SwiftUI

struct RecordingDetailView: View {
    @Bindable var store: RecordingStore
    let recordingId: UUID
    @State private var player = AudioPlayer()
    @State private var syncEngine = PlaybackSyncEngine()
    @State private var editingSpeaker: Speaker?
    @State private var activeTab: DetailTab = .summary

    #if !os(watchOS)
    var processingPipeline: ProcessingPipeline?
    var settingsManager: SettingsManager?
    var promptStore: PromptStore?
    @State private var showingAskAI = false
    @State private var isRunningPrompt = false
    @State private var searchQuery = ""
    #endif

    private enum DetailTab: Hashable {
        case summary, transcript, actionItems
    }

    private var recording: MapleRecording? {
        store.recordings.first { $0.id == recordingId }
    }

    var body: some View {
        if var recording = recording {
            ZStack(alignment: .bottomTrailing) {
                VStack(spacing: 0) {
                    // Tab bar
                    #if !os(watchOS)
                    UnderlineTabBar(
                        selection: $activeTab,
                        tabs: [
                            ("Summary", .summary),
                            ("Transcript", .transcript),
                            ("Action Items", .actionItems),
                        ]
                    )
                    .padding(.horizontal)
                    #endif

                    // Tab content
                    switch activeTab {
                    case .summary:
                        summaryTab(recording: recording)
                    case .transcript:
                        transcriptTab(recording: recording)
                    case .actionItems:
                        #if !os(watchOS)
                        actionItemsTab(recording: recording)
                        #else
                        emptyTranscriptPlaceholder
                        #endif
                    }
                }
                .safeAreaInset(edge: .bottom) {
                    if !recording.audioFiles.isEmpty {
                        PlaybackBar(
                            player: player,
                            onToggle: {
                                player.togglePlayPause()
                                if player.isPlaying {
                                    syncEngine.start(player: player, transcript: recording.transcript)
                                } else {
                                    syncEngine.stop()
                                }
                            },
                            onSeek: { time in
                                player.seek(to: time)
                            }
                        )
                    }
                }

                #if !os(watchOS)
                // AI FAB
                if !recording.transcript.isEmpty, promptStore != nil, settingsManager != nil {
                    Button {
                        showingAskAI = true
                    } label: {
                        Image(systemName: "sparkles")
                            .font(.title2)
                            .foregroundStyle(.white)
                            .frame(width: 56, height: 56)
                            .background(MapleTheme.primary, in: .circle)
                            .shadow(color: MapleTheme.primary.opacity(0.3), radius: 8, y: 4)
                    }
                    .buttonStyle(.plain)
                    .padding(.trailing, 20)
                    .padding(.bottom, 100) // Above playback bar
                }
                #endif
            }
            .background(MapleTheme.background)
            #if os(macOS)
            .navigationTitle("")
            .toolbar {
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 1) {
                        Text(recording.title)
                            .font(.headline)
                            .foregroundStyle(MapleTheme.textPrimary)
                        Text(recording.createdAt.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption2)
                            .foregroundStyle(MapleTheme.textSecondary)
                    }
                }
            }
            #elseif os(iOS)
            .navigationTitle(recording.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 1) {
                        Text(recording.title)
                            .font(.headline)
                            .foregroundStyle(MapleTheme.textPrimary)
                        Text(recording.createdAt.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption2)
                            .foregroundStyle(MapleTheme.textSecondary)
                    }
                }
            }
            #else
            .navigationTitle(recording.title)
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
            .sheet(isPresented: $showingAskAI) {
                if let promptStore, let settingsManager {
                    AskAISheet(
                        promptStore: promptStore,
                        settingsManager: settingsManager,
                        recording: recording,
                        store: store
                    )
                }
            }
            #endif
            .onAppear {
                loadAudio(recording: recording)
            }
        } else {
            ContentUnavailableView(
                "Recording Not Found",
                systemImage: "waveform",
                description: Text("This recording may have been deleted.")
            )
        }
    }

    // MARK: - Summary Tab

    @ViewBuilder
    private func summaryTab(recording: MapleRecording) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Meeting Overview card
                if !recording.summary.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("MEETING OVERVIEW")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundStyle(MapleTheme.primary)

                        Text(recording.summary)
                            .font(.body)
                            .foregroundStyle(MapleTheme.textPrimary)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(MapleTheme.surface, in: .rect(cornerRadius: 12))
                }

                // Key Highlights
                if !recording.transcript.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("KEY HIGHLIGHTS")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundStyle(MapleTheme.primary)

                        HStack(spacing: 12) {
                            highlightCard(
                                icon: "person.2.fill",
                                title: "\(recording.speakers.count)",
                                subtitle: "Speakers"
                            )
                            highlightCard(
                                icon: "clock.fill",
                                title: formatDuration(recording.duration),
                                subtitle: "Duration"
                            )
                            highlightCard(
                                icon: "text.alignleft",
                                title: "\(recording.transcript.count)",
                                subtitle: "Segments"
                            )
                        }
                    }
                }

                // Tags
                if !recording.tags.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("TAGS")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundStyle(MapleTheme.primary)

                        FlowLayout(spacing: 6) {
                            ForEach(recording.tags, id: \.self) { tag in
                                TagPill(tag: tag)
                            }
                        }
                    }
                }

                // Metadata
                HStack(spacing: 16) {
                    Label(formatDuration(recording.duration), systemImage: "clock")
                    Label(recording.createdAt.formatted(date: .abbreviated, time: .shortened), systemImage: "calendar")
                }
                .font(.subheadline)
                .foregroundStyle(MapleTheme.textSecondary)

                #if !os(watchOS)
                // Prompt Results
                PromptResultsView(
                    results: recording.promptResults,
                    onDelete: { result in
                        var updated = recording
                        updated.promptResults.removeAll { $0.id == result.id }
                        try? store.update(updated)
                    }
                )
                #endif

                #if !os(watchOS)
                if recording.transcript.isEmpty, let pipeline = processingPipeline {
                    processingIndicator(pipeline: pipeline)
                }
                #endif
            }
            .padding()
        }
    }

    // MARK: - Transcript Tab

    @ViewBuilder
    private func transcriptTab(recording: MapleRecording) -> some View {
        VStack(spacing: 0) {
            #if !os(watchOS)
            // Search bar
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(MapleTheme.textSecondary)
                TextField("Search transcript…", text: $searchQuery)
                    .font(.subheadline)
                if !searchQuery.isEmpty {
                    Button {
                        searchQuery = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(MapleTheme.textSecondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(MapleTheme.surfaceAlt, in: .rect(cornerRadius: 10))
            .padding(.horizontal)
            .padding(.vertical, 8)
            #endif

            ScrollView {
                #if !os(watchOS)
                if recording.transcript.isEmpty, let pipeline = processingPipeline {
                    processingIndicator(pipeline: pipeline)
                } else if recording.transcript.isEmpty {
                    emptyTranscriptPlaceholder
                        .padding(.top, 40)
                } else {
                    TranscriptView(
                        transcript: recording.transcript,
                        speakers: recording.speakers,
                        syncEngine: syncEngine,
                        searchQuery: searchQuery,
                        onSeekToWord: { word in
                            player.seek(to: word.start)
                        },
                        onRenameSpeaker: { speaker in
                            editingSpeaker = speaker
                        }
                    )
                    .padding(.horizontal)
                }
                #else
                emptyTranscriptPlaceholder
                    .padding(.top, 40)
                #endif
            }
        }
    }

    // MARK: - Action Items Tab

    #if !os(watchOS)
    @ViewBuilder
    private func actionItemsTab(recording: MapleRecording) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Find action items from prompt results
                let actionItemResults = recording.promptResults.filter {
                    $0.promptName.localizedCaseInsensitiveContains("action")
                }

                if !actionItemResults.isEmpty {
                    ForEach(actionItemResults) { result in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(result.promptName)
                                    .font(.headline)
                                    .foregroundStyle(MapleTheme.textPrimary)
                                Spacer()
                                ProviderBadge(provider: result.llmProvider)
                            }

                            // Parse result lines as checkable items
                            let items = parseActionItems(result.result)
                            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                                HStack(alignment: .top, spacing: 10) {
                                    Image(systemName: "circle")
                                        .font(.body)
                                        .foregroundStyle(MapleTheme.textSecondary)
                                    Text(item)
                                        .font(.body)
                                        .foregroundStyle(MapleTheme.textPrimary)
                                }
                            }
                        }
                        .padding()
                        .background(MapleTheme.surface, in: .rect(cornerRadius: 12))
                    }
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "checklist")
                            .font(.largeTitle)
                            .foregroundStyle(MapleTheme.textSecondary)

                        Text("No Action Items Yet")
                            .font(.headline)
                            .foregroundStyle(MapleTheme.textPrimary)

                        Text("Use the AI button to extract action items from this recording.")
                            .font(.subheadline)
                            .foregroundStyle(MapleTheme.textSecondary)
                            .multilineTextAlignment(.center)

                        if !recording.transcript.isEmpty {
                            Button {
                                showingAskAI = true
                            } label: {
                                Label("Extract Action Items", systemImage: "sparkles")
                                    .font(.headline)
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 24)
                                    .padding(.vertical, 12)
                                    .background(MapleTheme.primary, in: .capsule)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 60)
                }
            }
            .padding()
        }
    }
    #endif

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
    #endif

    private func highlightCard(icon: String, title: String, subtitle: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(MapleTheme.primary)
                .frame(width: 36, height: 36)
                .background(MapleTheme.primaryLight.opacity(0.15), in: .circle)

            Text(title)
                .font(.headline)
                .foregroundStyle(MapleTheme.textPrimary)

            Text(subtitle)
                .font(.caption)
                .foregroundStyle(MapleTheme.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(MapleTheme.surface, in: .rect(cornerRadius: 10))
    }

    // MARK: - Audio

    private func loadAudio(recording: MapleRecording) {
        let urls = recording.audioFiles.map { StorageLocation.recordingsURL.appendingPathComponent($0) }
        if urls.count == 1 {
            try? player.load(url: urls[0])
        } else if urls.count > 1 {
            try? player.loadChunks(urls: urls)
        }
    }

    // MARK: - Helpers

    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    #if !os(watchOS)
    private func parseActionItems(_ text: String) -> [String] {
        text.components(separatedBy: .newlines)
            .map { line in
                var cleaned = line.trimmingCharacters(in: .whitespaces)
                // Remove bullet markers
                for prefix in ["- ", "• ", "* ", "- [ ] ", "- [x] "] {
                    if cleaned.hasPrefix(prefix) {
                        cleaned = String(cleaned.dropFirst(prefix.count))
                    }
                }
                // Remove numbered list prefix
                if let range = cleaned.range(of: #"^\d+\.\s+"#, options: .regularExpression) {
                    cleaned = String(cleaned[range.upperBound...])
                }
                return cleaned.trimmingCharacters(in: .whitespaces)
            }
            .filter { !$0.isEmpty }
    }
    #endif
}
