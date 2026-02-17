import SwiftUI

struct RecordingDetailView: View {
    @Bindable var store: RecordingStore
    let recordingId: UUID
    @State private var player = AudioPlayer()
    @State private var syncEngine = PlaybackSyncEngine()
    @State private var editingSpeaker: Speaker?
    @State private var isLoadingAudio = false
    @State private var audioLoaded = false

    #if !os(watchOS)
    // Section expansion state
    @State private var isMeetingOverviewExpanded = true
    @State private var isDetailsExpanded = true
    @State private var isTagsExpanded = true
    @State private var isTranscriptExpanded = false
    @State private var isAIInsightsExpanded = true

    // Editing state
    @State private var editableTitle = ""
    @State private var isEditingSummary = false
    @State private var editableSummary = ""
    @State private var isEditingTags = false
    @State private var editableTagsText = ""
    #endif

    #if !os(watchOS)
    var processingPipeline: ProcessingPipeline?
    var settingsManager: SettingsManager?
    var promptStore: PromptStore?
    var autoProcessor: AutoProcessor?
    @State private var showingAskAI = false
    @State private var searchQuery = ""
    #endif

    private var recording: MapleRecording? {
        store.recordings.first { $0.id == recordingId }
    }

    var body: some View {
        if var recording = recording {
            ZStack(alignment: .bottomTrailing) {
                ScrollView {
                    VStack(spacing: 16) {
                        meetingOverviewSection(recording: recording)
                        detailsSection(recording: recording)
                        tagsSection(recording: recording)
                        transcriptSection(recording: recording)
                        #if !os(watchOS)
                        aiInsightsSection(recording: recording)
                        #endif

                        #if !os(watchOS)
                        if recording.transcript.isEmpty, let pipeline = processingPipeline {
                            processingIndicator(pipeline: pipeline)
                        }
                        #endif
                    }
                    .padding()
                }
                .safeAreaInset(edge: .bottom) {
                    if !recording.audioFiles.isEmpty {
                        if isLoadingAudio {
                            HStack(spacing: 8) {
                                ProgressView()
                                    .controlSize(.small)
                                Text("Downloading audio…")
                                    .font(.caption)
                                    .foregroundStyle(MapleTheme.textSecondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(MapleTheme.surface)
                        } else {
                            PlaybackBar(
                                player: player,
                                onToggle: {
                                    if !audioLoaded {
                                        Task { await loadAudioOnDemand(recording: recording) }
                                        return
                                    }
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
                    .padding(.bottom, 100)
                }
                #endif
            }
            .background(MapleTheme.background)
            #if os(watchOS)
            .navigationTitle(recording.title)
            #else
            .toolbar {
                ToolbarItem(placement: .principal) {
                    TextField("Title", text: $editableTitle)
                        .font(.headline)
                        .multilineTextAlignment(.center)
                        .onSubmit { commitTitleEdit(recording: recording) }
                }
                if let autoProcessor {
                    ToolbarItem(placement: .primaryAction) {
                        reprocessButton(recording: recording, autoProcessor: autoProcessor)
                    }
                }
            }
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #elseif os(macOS)
            .navigationTitle("")
            #endif
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
            #if !os(watchOS)
            .onAppear {
                editableTitle = recording.title
            }
            .onChange(of: recordingId) {
                if let rec = store.recordings.first(where: { $0.id == recordingId }) {
                    editableTitle = rec.title
                }
            }
            #endif
            .task {
                let micURLs = recording.audioFiles.map { StorageLocation.recordingsURL.appendingPathComponent($0) }
                let systemURLs = recording.systemAudioFiles.map { StorageLocation.recordingsURL.appendingPathComponent($0) }
                let allLocal = (micURLs + systemURLs).allSatisfy { ICloudFileDownloader.isDownloaded(url: $0) }
                if allLocal && !micURLs.isEmpty {
                    loadAudioSync(recording: recording)
                }
            }
        } else {
            ContentUnavailableView(
                "Recording Not Found",
                systemImage: "waveform",
                description: Text("This recording may have been deleted.")
            )
        }
    }

    // MARK: - Meeting Overview Section

    @ViewBuilder
    private func meetingOverviewSection(recording: MapleRecording) -> some View {
        #if os(watchOS)
        if !recording.summary.isEmpty {
            watchSection(title: "Meeting Overview") {
                Text(recording.summary)
                    .font(.body)
                    .foregroundStyle(MapleTheme.textPrimary)
            }
        }
        #else
        if !recording.summary.isEmpty || isEditingSummary {
            DisclosureGroup(isExpanded: $isMeetingOverviewExpanded) {
                if isEditingSummary {
                    VStack(alignment: .trailing, spacing: 8) {
                        TextEditor(text: $editableSummary)
                            .font(.body)
                            .foregroundStyle(MapleTheme.textPrimary)
                            .frame(minHeight: 80)
                            .scrollContentBackground(.hidden)

                        HStack(spacing: 12) {
                            Button("Cancel") {
                                isEditingSummary = false
                            }
                            .foregroundStyle(MapleTheme.textSecondary)

                            Button("Save") {
                                commitSummaryEdit(recording: recording)
                            }
                            .foregroundStyle(MapleTheme.primary)
                            .fontWeight(.semibold)
                        }
                    }
                } else {
                    Text(recording.summary)
                        .font(.body)
                        .foregroundStyle(MapleTheme.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                        .contextMenu {
                            Button("Edit Summary") {
                                editableSummary = recording.summary
                                isEditingSummary = true
                            }
                        }
                }
            } label: {
                Text("Meeting Overview")
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .foregroundStyle(MapleTheme.primary)
            }
            .disclosureGroupStyle(MapleSectionStyle())
        }
        #endif
    }

    // MARK: - Details Section

    @ViewBuilder
    private func detailsSection(recording: MapleRecording) -> some View {
        #if os(watchOS)
        watchSection(title: "Details") {
            VStack(alignment: .leading, spacing: 6) {
                detailRow(icon: "calendar", label: "Date", value: MarkdownSerializer.formattedDate(recording.createdAt))
                detailRow(icon: "clock", label: "Duration", value: MarkdownSerializer.formattedDuration(recording.duration))
                detailRow(icon: "person.2", label: "Speakers", value: "\(recording.speakers.count)")
            }
        }
        #else
        DisclosureGroup(isExpanded: $isDetailsExpanded) {
            VStack(alignment: .leading, spacing: 8) {
                detailRow(icon: "calendar", label: "Date", value: MarkdownSerializer.formattedDate(recording.createdAt))
                detailRow(icon: "clock", label: "Duration", value: MarkdownSerializer.formattedDuration(recording.duration))
                detailRow(icon: "person.2", label: "Speakers", value: "\(recording.speakers.count)")
            }
        } label: {
            Text("Details")
                .font(.subheadline)
                .fontWeight(.bold)
                .foregroundStyle(MapleTheme.primary)
        }
        .disclosureGroupStyle(MapleSectionStyle())
        #endif
    }

    private func detailRow(icon: String, label: String, value: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(MapleTheme.textSecondary)
                .frame(width: 20)
            Text(label)
                .font(.subheadline)
                .foregroundStyle(MapleTheme.textSecondary)
            Spacer()
            Text(value)
                .font(.subheadline)
                .foregroundStyle(MapleTheme.textPrimary)
        }
    }

    // MARK: - Tags Section

    @ViewBuilder
    private func tagsSection(recording: MapleRecording) -> some View {
        #if os(watchOS)
        if !recording.tags.isEmpty {
            watchSection(title: "Tags") {
                FlowLayout(spacing: 6) {
                    ForEach(recording.tags, id: \.self) { tag in
                        TagPill(tag: tag)
                    }
                }
            }
        }
        #else
        if !recording.tags.isEmpty || isEditingTags {
            DisclosureGroup(isExpanded: $isTagsExpanded) {
                if isEditingTags {
                    VStack(alignment: .trailing, spacing: 8) {
                        TextField("#tag1 #tag2 #tag3", text: $editableTagsText)
                            .font(.body)
                            .textFieldStyle(.plain)

                        HStack(spacing: 12) {
                            Button("Cancel") {
                                isEditingTags = false
                            }
                            .foregroundStyle(MapleTheme.textSecondary)

                            Button("Save") {
                                commitTagsEdit(recording: recording)
                            }
                            .foregroundStyle(MapleTheme.primary)
                            .fontWeight(.semibold)
                        }
                    }
                } else {
                    FlowLayout(spacing: 6) {
                        ForEach(recording.tags, id: \.self) { tag in
                            TagPill(tag: tag)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .contextMenu {
                        Button("Edit Tags") {
                            editableTagsText = recording.tags.map { "#\($0)" }.joined(separator: " ")
                            isEditingTags = true
                        }
                    }
                }
            } label: {
                Text("Tags")
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .foregroundStyle(MapleTheme.primary)
            }
            .disclosureGroupStyle(MapleSectionStyle())
        }
        #endif
    }

    // MARK: - Transcript Section

    @ViewBuilder
    private func transcriptSection(recording: MapleRecording) -> some View {
        #if os(watchOS)
        if !recording.transcript.isEmpty {
            watchSection(title: "Transcript") {
                Text("\(recording.transcript.count) segments — process on iPhone to view.")
                    .font(.body)
                    .foregroundStyle(MapleTheme.textSecondary)
                    .italic()
            }
        }
        #else
        if !recording.transcript.isEmpty {
            DisclosureGroup(isExpanded: $isTranscriptExpanded) {
                VStack(spacing: 0) {
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
                    .padding(.bottom, 8)

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
                }
            } label: {
                HStack {
                    Text("Transcript")
                        .font(.subheadline)
                        .fontWeight(.bold)
                        .foregroundStyle(MapleTheme.primary)
                    Text("\(recording.transcript.count) segments")
                        .font(.caption)
                        .foregroundStyle(MapleTheme.textSecondary)
                }
            }
            .disclosureGroupStyle(MapleSectionStyle())
        }
        #endif
    }

    // MARK: - watchOS Section Helper

    #if os(watchOS)
    private func watchSection<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline)
                .fontWeight(.bold)
                .foregroundStyle(MapleTheme.primary)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(MapleTheme.surface, in: .rect(cornerRadius: 12))
    }
    #endif

    // MARK: - AI Insights Section

    #if !os(watchOS)
    @ViewBuilder
    private func aiInsightsSection(recording: MapleRecording) -> some View {
        if !recording.promptResults.isEmpty {
            DisclosureGroup(isExpanded: $isAIInsightsExpanded) {
                VStack(spacing: 12) {
                    ForEach(recording.promptResults) { result in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(result.promptName)
                                    .font(.headline)
                                    .foregroundStyle(MapleTheme.textPrimary)
                                Spacer()
                                ProviderBadge(provider: result.llmProvider)
                                Button {
                                    var updated = recording
                                    updated.promptResults.removeAll { $0.id == result.id }
                                    try? store.update(updated)
                                } label: {
                                    Image(systemName: "trash")
                                        .font(.caption)
                                        .foregroundStyle(MapleTheme.textSecondary)
                                }
                                .buttonStyle(.plain)
                            }

                            Text(result.result)
                                .font(.body)
                                .foregroundStyle(MapleTheme.textPrimary)
                        }
                        .padding()
                        .background(MapleTheme.surfaceAlt, in: .rect(cornerRadius: 10))
                    }
                }
            } label: {
                Text("AI Insights")
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .foregroundStyle(MapleTheme.primary)
            }
            .disclosureGroupStyle(MapleSectionStyle())
        }
    }
    #endif

    // MARK: - Subviews

    #if !os(watchOS)
    @ViewBuilder
    private func reprocessButton(recording: MapleRecording, autoProcessor: AutoProcessor) -> some View {
        let isProcessing = autoProcessor.processingIds.contains(recording.id)
        Button {
            Task { await autoProcessor.reprocess(recording) }
        } label: {
            if isProcessing {
                ProgressView()
                    .controlSize(.small)
            } else {
                Label(
                    recording.transcript.isEmpty ? "Process" : "Reprocess",
                    systemImage: "arrow.clockwise"
                )
            }
        }
        .disabled(isProcessing || recording.audioFiles.isEmpty)
    }

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

    // MARK: - Editing

    #if !os(watchOS)
    private func commitTitleEdit(recording: MapleRecording) {
        let trimmed = editableTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != recording.title else {
            editableTitle = recording.title
            return
        }
        var updated = recording
        updated.title = trimmed
        updated.modifiedAt = Date()
        try? store.update(updated)
    }

    private func commitSummaryEdit(recording: MapleRecording) {
        let trimmed = editableSummary.trimmingCharacters(in: .whitespacesAndNewlines)
        var updated = recording
        updated.summary = trimmed
        updated.modifiedAt = Date()
        try? store.update(updated)
        isEditingSummary = false
    }

    private func commitTagsEdit(recording: MapleRecording) {
        let parsed = editableTagsText
            .components(separatedBy: .whitespaces)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .map { $0.hasPrefix("#") ? String($0.dropFirst()) : $0 }
            .filter { !$0.isEmpty }
        var updated = recording
        updated.tags = parsed
        updated.modifiedAt = Date()
        try? store.update(updated)
        isEditingTags = false
    }
    #endif

    // MARK: - Audio

    private func loadAudioSync(recording: MapleRecording) {
        let micURLs = recording.audioFiles.map { StorageLocation.recordingsURL.appendingPathComponent($0) }
        let systemURLs = recording.systemAudioFiles.map { StorageLocation.recordingsURL.appendingPathComponent($0) }

        if systemURLs.isEmpty {
            if micURLs.count == 1 {
                try? player.load(url: micURLs[0])
            } else if micURLs.count > 1 {
                try? player.loadChunks(urls: micURLs)
            }
        } else {
            try? player.loadWithSystemTracks(micURLs: micURLs, systemURLs: systemURLs)
        }
        audioLoaded = true
    }

    private func loadAudioOnDemand(recording: MapleRecording) async {
        let micURLs = recording.audioFiles.map { StorageLocation.recordingsURL.appendingPathComponent($0) }
        let systemURLs = recording.systemAudioFiles.map { StorageLocation.recordingsURL.appendingPathComponent($0) }
        let allURLs = micURLs + systemURLs
        guard !micURLs.isEmpty else { return }

        isLoadingAudio = true
        defer { isLoadingAudio = false }

        do {
            try await ICloudFileDownloader.ensureAllDownloaded(urls: allURLs)
        } catch {
            print("Failed to download audio from iCloud: \(error)")
            return
        }

        loadAudioSync(recording: recording)
        player.play()
        syncEngine.start(player: player, transcript: recording.transcript)
    }
}

// MARK: - Maple Section Style

#if !os(watchOS)
struct MapleSectionStyle: DisclosureGroupStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.25)) {
                    configuration.isExpanded.toggle()
                }
            } label: {
                HStack {
                    configuration.label
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(MapleTheme.textSecondary)
                        .rotationEffect(.degrees(configuration.isExpanded ? 90 : 0))
                        .animation(.easeInOut(duration: 0.25), value: configuration.isExpanded)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .buttonStyle(.plain)

            if configuration.isExpanded {
                configuration.content
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
            }
        }
        .background(MapleTheme.surface, in: .rect(cornerRadius: 12))
    }
}
#endif
