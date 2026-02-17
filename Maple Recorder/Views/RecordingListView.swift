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
    @State private var searchText = ""
    @State private var listTab: ListTab = .all
    #if !os(watchOS)
    @State private var activePipeline: ProcessingPipeline?
    @State private var processingRecordingId: UUID?
    @State private var showingSettings = false
    #endif

    private enum ListTab: Hashable {
        case all, tags
    }

    var body: some View {
        #if os(macOS)
        NavigationSplitView {
            listContent
                .navigationSplitViewColumnWidth(min: 350, ideal: 450, max: 600)
                .sheet(isPresented: $showingSettings) {
                    SettingsView(settingsManager: settingsManager, promptStore: promptStore)
                }
        } detail: {
            detailColumn
        }
        .tint(MapleTheme.primary)
        #else
        NavigationStack {
            listContent
                .navigationDestination(for: UUID.self) { id in
                    #if !os(watchOS)
                    RecordingDetailView(
                        store: store,
                        recordingId: id,
                        processingPipeline: processingRecordingId == id ? activePipeline : nil,
                        settingsManager: settingsManager,
                        promptStore: promptStore
                    )
                    #else
                    RecordingDetailView(
                        store: store,
                        recordingId: id
                    )
                    #endif
                }
                #if !os(watchOS)
                .sheet(isPresented: $showingSettings) {
                    SettingsView(settingsManager: settingsManager, promptStore: promptStore)
                }
                #endif
        }
        .tint(MapleTheme.primary)
        #endif
    }

    // MARK: - List Content

    private var listContent: some View {
        VStack(spacing: 0) {
            headerView

            UnderlineTabBar(
                selection: $listTab,
                tabs: [
                    ("All Recordings", .all),
                    ("Tags", .tags),
                ]
            )
            .padding(.horizontal)

            switch listTab {
            case .all:
                allRecordingsTab
            case .tags:
                tagsTab
            }
        }
        .background(MapleTheme.background)
        .overlay(alignment: .bottom) {
            if recorder.isRecording {
                recordingOverlay
            } else {
                recordFAB
            }
        }
    }

    // MARK: - macOS Detail Column

    #if os(macOS)
    @ViewBuilder
    private var detailColumn: some View {
        if let id = selectedRecordingId {
            RecordingDetailView(
                store: store,
                recordingId: id,
                processingPipeline: processingRecordingId == id ? activePipeline : nil,
                settingsManager: settingsManager,
                promptStore: promptStore
            )
        } else {
            ContentUnavailableView(
                "No Recording Selected",
                systemImage: "waveform",
                description: Text("Select a recording from the sidebar")
            )
        }
    }
    #endif

    // MARK: - Header

    private var headerView: some View {
        HStack {
            Text("Maple Recorder")
                .font(.system(.title, design: .rounded, weight: .bold))
                .foregroundStyle(MapleTheme.primary)

            Spacer()

            #if !os(watchOS)
            Button { showingSettings = true } label: {
                Image(systemName: "gearshape")
                    .font(.title3)
                    .foregroundStyle(MapleTheme.textSecondary)
            }
            .buttonStyle(.plain)
            #endif
        }
        .padding(.horizontal)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    // MARK: - All Recordings Tab

    private var allRecordingsTab: some View {
        ScrollView {
            #if !os(watchOS)
            modelStatusBanner
                .padding(.horizontal)
            #endif

            if filteredRecordings.isEmpty && !recorder.isRecording {
                ContentUnavailableView(
                    "No Recordings",
                    systemImage: "waveform",
                    description: Text("Tap the record button to start")
                )
                .padding(.top, 60)
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(filteredRecordings) { recording in
                        recordingLink(recording)

                        Divider()
                            .foregroundStyle(MapleTheme.border.opacity(0.15))
                            .padding(.leading, 16)
                    }
                }
            }

            // Extra space for FAB
            Spacer()
                .frame(height: 100)
        }
    }

    // MARK: - Tags Tab

    private var tagsTab: some View {
        ScrollView {
            if allTags.isEmpty {
                ContentUnavailableView(
                    "No Tags Yet",
                    systemImage: "tag",
                    description: Text("Tags are generated automatically when recordings are processed")
                )
                .padding(.top, 60)
            } else {
                LazyVStack(alignment: .leading, spacing: 16) {
                    ForEach(allTags, id: \.self) { tag in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                TagPill(tag: tag)
                                Text("\(recordingsForTag(tag).count)")
                                    .font(.caption)
                                    .foregroundStyle(MapleTheme.textSecondary)
                            }
                            .padding(.horizontal)

                            ForEach(recordingsForTag(tag)) { recording in
                                recordingLink(recording)
                            }

                            Divider()
                                .foregroundStyle(MapleTheme.border.opacity(0.15))
                        }
                    }
                }
                .padding(.top, 8)
            }

            Spacer()
                .frame(height: 100)
        }
    }

    // MARK: - Model Status

    #if !os(watchOS)
    @ViewBuilder
    private var modelStatusBanner: some View {
        if modelManager.isDownloading {
            VStack(spacing: 6) {
                ProgressView(value: modelManager.downloadProgress)
                    .tint(MapleTheme.primary)

                Text(modelManager.downloadStep.rawValue)
                    .font(.caption)
                    .foregroundStyle(MapleTheme.textSecondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
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

    // MARK: - Recording Link

    @ViewBuilder
    private func recordingLink(_ recording: MapleRecording) -> some View {
        let row = RecordingRow(recording: recording, isProcessing: isProcessing(recording))
        #if os(macOS)
        Button { selectedRecordingId = recording.id } label: { row }
            .buttonStyle(.plain)
            .background(
                selectedRecordingId == recording.id ? MapleTheme.surfaceHover : .clear,
                in: .rect(cornerRadius: 6)
            )
        #else
        NavigationLink(value: recording.id) { row }
            .buttonStyle(.plain)
        #endif
    }

    // MARK: - Record FAB

    private var recordFAB: some View {
        VStack(spacing: 0) {
            #if os(macOS)
            if !recorder.isRecording {
                Toggle(isOn: $recorder.includeSystemAudio) {
                    Label("Include system audio", systemImage: "speaker.wave.2")
                        .font(.caption)
                        .foregroundStyle(MapleTheme.textSecondary)
                }
                .toggleStyle(.checkbox)
                .padding(.bottom, 8)
            }
            #endif

            Button {
                startRecording()
            } label: {
                Image(systemName: "mic.fill")
                    .font(.title2)
                    .foregroundStyle(.white)
                    .frame(width: 64, height: 64)
                    .background(MapleTheme.primary, in: .circle)
                    .shadow(color: MapleTheme.primary.opacity(0.3), radius: 8, y: 4)
            }
            .buttonStyle(.plain)
        }
        .padding(.bottom, 24)
    }

    // MARK: - Recording Overlay

    private var recordingOverlay: some View {
        VStack(spacing: 12) {
            ZStack {
                PulsingWaveform(audioLevel: recorder.audioLevel)

                Button {
                    stopRecording()
                } label: {
                    Image(systemName: "stop.fill")
                        .font(.title2)
                        .foregroundStyle(.white)
                        .frame(width: 64, height: 64)
                        .background(MapleTheme.error, in: .circle)
                        .shadow(color: MapleTheme.error.opacity(0.3), radius: 8, y: 4)
                }
                .buttonStyle(.plain)
            }
            .frame(width: 180, height: 180)

            Text(formatTime(recorder.elapsedTime))
                .font(.system(.title3, design: .monospaced))
                .foregroundStyle(MapleTheme.textPrimary)

            Text("Recording")
                .font(.caption)
                .foregroundStyle(MapleTheme.textSecondary)
        }
        .padding(.top, 16)
        .padding(.bottom, 32)
        .frame(maxWidth: .infinity)
        .background(
            Rectangle()
                .fill(MapleTheme.surface)
                .shadow(color: .black.opacity(0.08), radius: 12, y: -4)
                .mask(alignment: .top) {
                    UnevenRoundedRectangle(topLeadingRadius: 20, topTrailingRadius: 20)
                        .frame(height: 500)
                }
                .ignoresSafeArea(.container, edges: .bottom)
        )
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
        let urls = recorder.stopRecording()
        guard !urls.isEmpty else { return }

        let now = Date()
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        let title = "Recording \(formatter.string(from: now))"

        // Copy all chunk files to recordings directory
        var audioFileNames: [String] = []
        for url in urls {
            let fileName = url.lastPathComponent
            let destURL = StorageLocation.recordingsURL.appendingPathComponent(fileName)
            try? FileManager.default.copyItem(at: url, to: destURL)
            audioFileNames.append(fileName)
        }

        let recording = MapleRecording(
            title: title,
            audioFiles: audioFileNames,
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

    // MARK: - Computed

    private var filteredRecordings: [MapleRecording] {
        if searchText.isEmpty {
            return store.recordings
        }
        return store.recordings.filter {
            $0.title.localizedCaseInsensitiveContains(searchText)
                || $0.summary.localizedCaseInsensitiveContains(searchText)
        }
    }

    private var allTags: [String] {
        let tagSet = Set(store.recordings.flatMap(\.tags))
        return tagSet.sorted()
    }

    private func recordingsForTag(_ tag: String) -> [MapleRecording] {
        store.recordings.filter { $0.tags.contains(tag) }
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
    let isProcessing: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Title + duration + processing
            HStack(alignment: .center) {
                Text(recording.title)
                    .font(.headline)
                    .foregroundStyle(MapleTheme.textPrimary)
                    .lineLimit(1)

                if isProcessing {
                    ProgressView()
                        .controlSize(.small)
                }

                Spacer()

                Text(formatDuration(recording.duration))
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(MapleTheme.textSecondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(MapleTheme.surfaceAlt, in: .capsule)
            }

            // Date + tags
            HStack(spacing: 6) {
                Text(recording.createdAt.formatted(date: .abbreviated, time: .omitted).uppercased())
                    .font(.caption2)
                    .foregroundStyle(MapleTheme.textSecondary)

                if !recording.tags.isEmpty {
                    Text("·")
                        .foregroundStyle(MapleTheme.textSecondary)

                    ForEach(recording.tags.prefix(3), id: \.self) { tag in
                        TagPill(tag: tag)
                    }
                }
            }

            // Summary preview
            if !recording.summary.isEmpty {
                Text(recording.summary)
                    .font(.subheadline)
                    .foregroundStyle(MapleTheme.textSecondary)
                    .lineLimit(2)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
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
