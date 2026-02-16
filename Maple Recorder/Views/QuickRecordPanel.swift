#if os(macOS)
import AppKit
import SwiftUI

// MARK: - Floating NSPanel

final class FloatingRecordPanel: NSPanel {
    private let onClose: () -> Void

    init<Content: View>(content: @escaping () -> Content, onClose: @escaping () -> Void) {
        self.onClose = onClose
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 80),
            styleMask: [.borderless, .nonactivatingPanel, .titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isMovableByWindowBackground = true
        hidesOnDeactivate = true
        animationBehavior = .utilityWindow
        backgroundColor = .clear
        isOpaque = false

        for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            standardWindowButton(button)?.isHidden = true
        }

        contentView = NSHostingView(rootView: content())
    }

    override func resignKey() {
        super.resignKey()
        close()
    }

    override func close() {
        super.close()
        onClose()
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) {
        close()
    }
}

// MARK: - Panel Controller

@Observable
@MainActor
final class QuickRecordController {
    private var panel: FloatingRecordPanel?
    var store: RecordingStore?
    var modelManager: ModelManager?
    var settingsManager: SettingsManager?

    var isOpen: Bool { panel != nil }

    func toggle() {
        if panel != nil {
            panel?.close()
            panel = nil
        } else {
            open()
        }
    }

    func open() {
        guard panel == nil else { return }
        guard let store, let modelManager, let settingsManager else { return }

        let newPanel = FloatingRecordPanel(
            content: { [weak self] in
                QuickRecordView(
                    store: store,
                    modelManager: modelManager,
                    settingsManager: settingsManager,
                    onDismiss: { self?.dismiss() }
                )
            },
            onClose: { [weak self] in self?.panel = nil }
        )

        // Center horizontally, position in upper third of screen
        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let panelWidth: CGFloat = 480
            let panelHeight: CGFloat = 80
            let x = screenFrame.midX - panelWidth / 2
            let y = screenFrame.maxY - panelHeight - screenFrame.height * 0.25
            newPanel.setFrame(NSRect(x: x, y: y, width: panelWidth, height: panelHeight), display: true)
        }

        NSApplication.shared.activate()
        newPanel.makeKeyAndOrderFront(nil)
        newPanel.orderFrontRegardless()
        self.panel = newPanel
    }

    func dismiss() {
        panel?.close()
        panel = nil
    }
}

// MARK: - Quick Record SwiftUI View

struct QuickRecordView: View {
    @Bindable var store: RecordingStore
    var modelManager: ModelManager
    var settingsManager: SettingsManager
    var onDismiss: () -> Void

    @State private var recorder = AudioRecorder()
    @State private var recordingURL: URL?

    var body: some View {
        HStack(spacing: 16) {
            // Record/Stop button
            Button {
                if recorder.isRecording {
                    stopRecording()
                } else {
                    startRecording()
                }
            } label: {
                Image(systemName: recorder.isRecording ? "stop.circle.fill" : "mic.circle.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(recorder.isRecording ? MapleTheme.error : MapleTheme.primary)
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 4) {
                if recorder.isRecording {
                    Text(formatTime(recorder.elapsedTime))
                        .font(.system(.title2, design: .monospaced, weight: .medium))
                        .foregroundStyle(MapleTheme.textPrimary)

                    // Mini waveform
                    HStack(spacing: 1) {
                        ForEach(Array(recorder.amplitudeSamples.suffix(30).enumerated()), id: \.offset) { _, sample in
                            RoundedRectangle(cornerRadius: 1)
                                .fill(MapleTheme.primary)
                                .frame(width: 3, height: max(2, CGFloat(sample) * 24))
                        }
                    }
                    .frame(height: 24, alignment: .center)
                } else {
                    Text("Quick Record")
                        .font(.system(.title2, design: .rounded, weight: .medium))
                        .foregroundStyle(MapleTheme.textPrimary)

                    Text("⌘⇧R to toggle • Esc to close")
                        .font(.caption)
                        .foregroundStyle(MapleTheme.textSecondary)
                }
            }

            Spacer()

            if recorder.isRecording {
                // Include system audio toggle
                Toggle(isOn: .constant(recorder.includeSystemAudio)) {
                    Image(systemName: "speaker.wave.2")
                }
                .toggleStyle(.checkbox)
                .disabled(true)
                .help("System audio (set before recording)")
            }
        }
        .padding(20)
        .frame(width: 480)
        .background(.ultraThinMaterial, in: .rect(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(MapleTheme.border.opacity(0.3), lineWidth: 0.5)
        )
    }

    private func startRecording() {
        Task {
            do {
                recordingURL = try await recorder.startRecording()
            } catch {
                print("Quick record failed: \(error)")
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
        try? store.save(recording)

        // Trigger processing
        if modelManager.isReady {
            Task {
                let pipeline = modelManager.createPipeline()
                try? await store.processRecording(
                    recording,
                    pipeline: pipeline,
                    transcription: modelManager.transcriptionManager,
                    diarization: modelManager.diarizationManager,
                    summarizationProvider: settingsManager.preferredProvider
                )
            }
        }

        onDismiss()
    }

    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}
#endif
