import SwiftUI

struct RecordingListView: View {
    @Bindable var store: RecordingStore
    #if !os(watchOS)
    var modelManager: ModelManager
    @Bindable var settingsManager: SettingsManager
    @Bindable var promptStore: PromptStore
    var autoProcessor: AutoProcessor?
    var calendarManager: CalendarManager?
    #endif
    #if os(macOS)
    var miniRecordingController: MiniRecordingController?
    #endif
    @State private var recorder = AudioRecorder()
    #if !os(watchOS)
    @State private var videoRecorder = VideoRecorder()
    @State private var isVideoEnabled = false
    #endif
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
                    SettingsView(settingsManager: settingsManager, promptStore: promptStore, calendarManager: calendarManager)
                }
        } detail: {
            detailColumn
        }
        .tint(MapleTheme.primary)
        .onChange(of: store.pendingSelectionId) { _, newId in
            if let newId {
                selectedRecordingId = newId
                store.pendingSelectionId = nil
            }
        }
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
                        promptStore: promptStore,
                        autoProcessor: autoProcessor
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
                    SettingsView(settingsManager: settingsManager, promptStore: promptStore, calendarManager: calendarManager)
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
            recordFAB
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
                promptStore: promptStore,
                autoProcessor: autoProcessor
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
                if !store.hasLoadedOnce && searchText.isEmpty {
                    // Still loading from disk — avoid a scary "No Recordings" flash.
                    VStack(spacing: 12) {
                        ProgressView()
                            .tint(MapleTheme.primary)
                        Text("Loading recordings…")
                            .font(.subheadline)
                            .foregroundStyle(MapleTheme.textSecondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 80)
                } else {
                    ContentUnavailableView(
                        "No Recordings",
                        systemImage: "waveform",
                        description: Text("Tap the record button to start")
                    )
                    .padding(.top, 60)
                }
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
        #if os(macOS)
        RecordingRowLink(
            recording: recording,
            isProcessing: isProcessing(recording),
            isSelected: selectedRecordingId == recording.id,
            onSelect: { selectedRecordingId = recording.id }
        )
        #else
        RecordingRowLink(
            recording: recording,
            isProcessing: isProcessing(recording)
        )
        #endif
    }

    // MARK: - Record FAB

    private var recordFAB: some View {
        VStack(spacing: 8) {
            #if !os(watchOS)
            // Gated on the session's actual running state, not the isVideoEnabled
            // toggle intent: tearing down this view's AVCaptureVideoPreviewLayer
            // deallocates it on the main thread, which calls back into the
            // session (commitConfiguration) to detach. If that races with
            // session.stopRunning() running concurrently on videoRecorder's
            // background queue, AVFoundation deadlocks the two threads against
            // each other (each waiting on a lock the other holds) — the app
            // beachballs. Waiting for isSessionRunning to actually flip false
            // (which only happens after stopRunning() has already returned)
            // guarantees the view's teardown happens strictly after, never
            // concurrently with, that call.
            if videoRecorder.isSessionRunning {
                CameraPreviewView(session: videoRecorder.session)
                    .frame(width: 160, height: 120)
                    .clipShape(.rect(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(MapleTheme.border, lineWidth: 1)
                    )
            }

            if let captureError = videoRecorder.captureError {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(MapleTheme.error)
                    Text(captureError)
                        .font(.caption2)
                        .foregroundStyle(MapleTheme.textSecondary)
                        .lineLimit(2)
                }
                .padding(.horizontal, 12)
            }
            #endif

            ZStack {
                if recorder.isRecording {
                    PulsingWaveform(audioLevel: recorder.audioLevel)
                }

                Button {
                    if recorder.isRecording {
                        stopRecording()
                    } else {
                        startRecording()
                    }
                } label: {
                    Image(systemName: recorder.isRecording ? "stop.fill" : "mic.fill")
                        .font(.title2)
                        .foregroundStyle(.white)
                        .frame(width: 64, height: 64)
                        .background(MapleTheme.primary, in: .circle)
                        .shadow(color: MapleTheme.primary.opacity(0.3), radius: 8, y: 4)
                }
                .buttonStyle(.plain)
            }
            .frame(width: 64, height: 64)

            if recorder.isRecording {
                Text(formatTime(recorder.elapsedTime))
                    .font(.system(.caption, design: .monospaced, weight: .medium))
                    .foregroundStyle(.white)
            } else {
                HStack(spacing: 8) {
                    #if os(macOS)
                    RecordingOptionChip(
                        title: "System audio",
                        systemImage: "speaker.wave.2",
                        isOn: $recorder.includeSystemAudio
                    )
                    #endif
                    #if !os(watchOS)
                    RecordingOptionChip(
                        title: "Video",
                        systemImage: "video.fill",
                        isOn: $isVideoEnabled
                    )
                    #endif
                }
            }
        }
        .padding(.bottom, 16)
        .padding(.top, 10)
        .frame(maxWidth: .infinity)
        .background(
            LinearGradient(
                colors: [
                    MapleTheme.background.opacity(0),
                    MapleTheme.background.opacity(0.8),
                    MapleTheme.background.opacity(0.9),
                    MapleTheme.background,
                    MapleTheme.background
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea(.container, edges: .bottom)
        )
        #if !os(watchOS)
        .onChange(of: isVideoEnabled) { _, newValue in
            if newValue {
                Task { await enableVideoPreview() }
            } else {
                videoRecorder.stopSession()
            }
        }
        #endif
    }

    #if !os(watchOS)
    private func enableVideoPreview() async {
        videoRecorder.captureError = nil
        let granted = await videoRecorder.requestPermissionIfNeeded()
        guard granted else {
            isVideoEnabled = false
            videoRecorder.captureError = "Camera access denied. Enable it in System Settings > Privacy > Camera."
            return
        }
        videoRecorder.startSession(preferredDeviceID: settingsManager.preferredCameraID)
    }
    #endif

    // MARK: - Actions

    private func startRecording() {
        #if os(macOS)
        miniRecordingController?.recorder = recorder
        miniRecordingController?.onStopRequested = { [self] in
            stopRecording()
        }
        #endif
        Task {
            do {
                recordingURL = try await recorder.startRecording()
                #if !os(watchOS)
                if isVideoEnabled, let recordingId = recorder.recordingId {
                    videoRecorder.startRecording(id: recordingId)
                }
                #endif
            } catch {
                print("Failed to start recording: \(error)")
            }
        }
    }

    private func stopRecording() {
        #if os(macOS)
        miniRecordingController?.recorder = nil
        miniRecordingController?.onStopRequested = nil
        miniRecordingController?.dismissPanel()
        #endif

        let duration = recorder.elapsedTime
        let result = recorder.stopRecording()
        guard !result.micURLs.isEmpty else { return }

        #if !os(watchOS)
        let wasVideoEnabled = isVideoEnabled
        isVideoEnabled = false
        if !wasVideoEnabled {
            videoRecorder.stopSession()
        }
        // If video was enabled, the session is stopped in attachVideoFile(to:) —
        // only after the movie file finishes writing. Stopping it here instead
        // would tear the capture session down while stopRecording() below is
        // still trying to finalize the file through it, deadlocking AVFoundation.
        #endif

        let now = Date()
        let title: String
        #if !os(watchOS)
        let calTitle = settingsManager.calendarEnabled
            ? calendarManager?.currentMeetingTitle(calendarIdentifiers: settingsManager.selectedCalendarIdentifiers)
            : nil
        switch settingsManager.calendarTitleMode {
        case .exactName where calTitle != nil:
            title = calTitle!
        case .hint where calTitle != nil:
            title = "\(calTitle!) — Recording"
        default:
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
            title = "Recording \(formatter.string(from: now))"
        }
        #else
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        title = "Recording \(formatter.string(from: now))"
        #endif

        // Copy all mic chunk files to recordings directory
        var audioFileNames: [String] = []
        for url in result.micURLs {
            let fileName = url.lastPathComponent
            let destURL = StorageLocation.recordingsURL.appendingPathComponent(fileName)
            try? FileManager.default.copyItem(at: url, to: destURL)
            audioFileNames.append(fileName)
        }

        // Copy system audio chunk files
        var systemAudioFileNames: [String] = []
        for url in result.systemURLs {
            let fileName = url.lastPathComponent
            let destURL = StorageLocation.recordingsURL.appendingPathComponent(fileName)
            try? FileManager.default.copyItem(at: url, to: destURL)
            systemAudioFileNames.append(fileName)
        }

        let recordingId = recorder.recordingId ?? UUID()
        let recording = MapleRecording(
            id: recordingId,
            title: title,
            audioFiles: audioFileNames,
            systemAudioFiles: systemAudioFileNames,
            duration: duration,
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
        if wasVideoEnabled {
            Task {
                await attachVideoFile(to: recordingId)
            }
        }

        // Kick off processing pipeline
        if modelManager.isReady {
            Task {
                await processRecording(recording)
            }
        }
        #endif
    }

    #if !os(watchOS)
    private func attachVideoFile(to recordingId: UUID) async {
        let tempURL = await videoRecorder.stopRecording()
        videoRecorder.stopSession()
        guard let tempURL else { return }
        let destURL = StorageLocation.recordingsURL.appendingPathComponent(tempURL.lastPathComponent)
        try? FileManager.default.copyItem(at: tempURL, to: destURL)

        guard var recording = store.recordings.first(where: { $0.id == recordingId }) else { return }
        recording.videoFile = destURL.lastPathComponent
        try? store.update(recording)
    }
    #endif

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

// MARK: - Row Link (whole-cell tappable + hover highlight)

private struct RecordingRowLink: View {
    let recording: MapleRecording
    let isProcessing: Bool
    #if os(macOS)
    let isSelected: Bool
    let onSelect: () -> Void
    #endif
    @State private var isHovering = false

    var body: some View {
        // `.contentShape` makes the entire padded row hit-testable, not just the text.
        let row = RecordingRow(recording: recording, isProcessing: isProcessing)
            .contentShape(Rectangle())

        #if os(macOS)
        Button(action: onSelect) { row }
            .buttonStyle(.plain)
            .background(rowBackground, in: .rect(cornerRadius: 6))
            .onHover { isHovering = $0 }
        #elseif os(iOS)
        NavigationLink(value: recording.id) { row }
            .buttonStyle(.plain)
            .background(
                isHovering ? MapleTheme.surfaceHover.opacity(0.5) : .clear,
                in: .rect(cornerRadius: 6)
            )
            .onHover { isHovering = $0 }
        #else
        NavigationLink(value: recording.id) { row }
            .buttonStyle(.plain)
        #endif
    }

    #if os(macOS)
    private var rowBackground: Color {
        if isSelected { return MapleTheme.surfaceHover }
        if isHovering { return MapleTheme.surfaceHover.opacity(0.5) }
        return .clear
    }
    #endif
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
                        TagPill(tag: tag, maxWidth: 88)
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
