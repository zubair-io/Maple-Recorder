#if os(macOS)
import AppKit
import CoreGraphics
import CoreVideo
import ImageIO
import Observation
import ScreenCaptureKit
import SwiftUI
import UniformTypeIdentifiers
import Vision

struct CapturedTimelineScreenshot {
    let sourceURL: URL
    let timestamp: TimeInterval
}

struct RecordingAccessoryResult {
    let screenshots: [CapturedTimelineScreenshot]
    let userNotes: String
}

/// Owns the macOS-only helpers that accompany an audio recording: private notes,
/// focused-window screenshots, and Dock suppression.
@MainActor
final class RecordingSessionAccessories {
    private let screenshotCapture = FocusedWindowScreenshotCapture()
    private let notesController = RecordingNotesController()
    private var isRunning = false
    private var settingsManager: SettingsManager?
    private var previousAssistTurn: AssistTurnSnapshot?

    var onWarning: ((String) -> Void)?

    func start(recordingID: UUID, settingsManager: SettingsManager?) {
        guard !isRunning else { return }
        isRunning = true
        let effectiveSettingsManager = settingsManager ?? SettingsManager()
        self.settingsManager = effectiveSettingsManager
        previousAssistTurn = nil

        // Remember the presentation app before the notes panel becomes key.
        let currentPID = ProcessInfo.processInfo.processIdentifier
        let initialTargetPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let externalTargetPID = initialTargetPID == currentPID ? nil : initialTargetPID

        RecordingPresentationManager.shared.beginRecording()
        screenshotCapture.onWarning = { [weak self] warning in
            self?.onWarning?(warning)
        }
        notesController.show(settingsManager: effectiveSettingsManager) { [weak self] notes, sourceImage in
            guard let self else { throw AssistError.notAvailable }
            return try await self.generateAssist(notes: notes, sourceImage: sourceImage)
        }
        screenshotCapture.onRelevantFrame = { [weak self] image in
            self?.notesController.requestAutomaticAssist(image: image)
        }
        screenshotCapture.start(recordingID: recordingID, initialTargetPID: externalTargetPID)
    }

    func stop() -> RecordingAccessoryResult {
        guard isRunning else {
            return RecordingAccessoryResult(screenshots: [], userNotes: "")
        }
        isRunning = false

        let screenshots = screenshotCapture.stop()
        screenshotCapture.onRelevantFrame = nil
        let notes = notesController.stop()
        settingsManager = nil
        previousAssistTurn = nil
        RecordingPresentationManager.shared.endRecording()
        return RecordingAccessoryResult(screenshots: screenshots, userNotes: notes)
    }

    private func generateAssist(notes: String, sourceImage: CGImage?) async throws -> String {
        guard let settingsManager else { throw AssistError.notAvailable }
        let provider = settingsManager.preferredProvider
        guard provider != .none,
              let service = LLMServiceFactory.service(for: provider),
              service.isAvailable else {
            throw AssistError.providerUnavailable(provider)
        }

        let includeCloudImage = (provider == .claude || provider == .openai)
            && settingsManager.shareAssistScreenshotsWithCloudAI
        let screenContext = try await screenshotCapture.assistContext(
            from: sourceImage,
            includeImage: includeCloudImage
        )
        let prompt = settingsManager.assistPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let systemPrompt = prompt.isEmpty ? AppSettings.defaultAssistPrompt : prompt

        let contextBudget = max(1_000, provider.maxChunkCharacters - systemPrompt.count - 400)
        let requestContext = AssistContextBuilder.build(
            currentScreenText: screenContext.recognizedText,
            currentImage: screenContext.image,
            notes: notes,
            previousTurn: previousAssistTurn,
            characterBudget: contextBudget,
            includeImages: includeCloudImage
        )

        let response = try await service.generate(
            systemPrompt: systemPrompt,
            userMessage: requestContext.userMessage,
            images: requestContext.images
        )
        previousAssistTurn = AssistTurnSnapshot(
            recognizedText: screenContext.recognizedText,
            image: screenContext.image,
            response: response
        )
        return response
    }
}

private enum AssistError: LocalizedError {
    case notAvailable
    case providerUnavailable(LLMProvider)

    var errorDescription: String? {
        switch self {
        case .notAvailable:
            "Assist is not available right now."
        case .providerUnavailable(let provider):
            provider == .none
                ? "Choose an AI provider in Settings to use Assist."
                : "\(provider.displayName) is unavailable. Check its model or API key in Settings."
        }
    }
}

// MARK: - Presentation mode

/// Keeps Maple out of the Dock while recording and applies AppKit's legacy
/// `sharingType = .none` as a best-effort compatibility layer. Modern macOS does
/// not guarantee that the sharing flag excludes a visible window from another
/// app's full-display capture, so callers should still share the presentation
/// window to reliably keep the separate notes panel private.
@MainActor
private final class RecordingPresentationManager {
    static let shared = RecordingPresentationManager()

    private var recordingCount = 0
    private var originalActivationPolicy: NSApplication.ActivationPolicy?
    private var protectedWindows: [(window: NSWindow, sharingType: NSWindow.SharingType)] = []
    private var keyWindowObserver: NSObjectProtocol?

    func beginRecording() {
        recordingCount += 1
        guard recordingCount == 1 else { return }

        originalActivationPolicy = NSApplication.shared.activationPolicy()
        NSApplication.shared.windows.forEach(protect)
        keyWindowObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let window = notification.object as? NSWindow else { return }
            Task { @MainActor [weak self] in self?.protect(window) }
        }

        // Accessory apps keep their windows usable but do not appear in the Dock.
        NSApplication.shared.setActivationPolicy(.accessory)
    }

    func endRecording() {
        guard recordingCount > 0 else { return }
        recordingCount -= 1
        guard recordingCount == 0 else { return }

        if let keyWindowObserver {
            NotificationCenter.default.removeObserver(keyWindowObserver)
            self.keyWindowObserver = nil
        }
        for protectedWindow in protectedWindows {
            protectedWindow.window.sharingType = protectedWindow.sharingType
        }
        protectedWindows.removeAll()

        NSApplication.shared.setActivationPolicy(originalActivationPolicy ?? .regular)
        originalActivationPolicy = nil
    }

    private func protect(_ window: NSWindow) {
        guard !protectedWindows.contains(where: { $0.window === window }) else { return }
        protectedWindows.append((window, window.sharingType))
        window.sharingType = .none
    }
}

// MARK: - Notes panel

@Observable
@MainActor
private final class RecordingNotesModel {
    var text = ""
    var isAutoAssistEnabled: Bool
    var isAssisting = false
    var assistResponse = ""
    var assistError: String?

    init(isAutoAssistEnabled: Bool) {
        self.isAutoAssistEnabled = isAutoAssistEnabled
    }
}

@MainActor
private final class RecordingNotesPanel: NSPanel {
    init(content: some View) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 560),
            styleMask: [.titled, .resizable, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        title = "Recording Notes"
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = false
        isReleasedWhenClosed = false
        animationBehavior = .utilityWindow
        isMovableByWindowBackground = true
        sharingType = .none
        minSize = NSSize(width: 340, height: 420)
        contentView = NSHostingView(rootView: content)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
private final class RecordingNotesController {
    typealias AssistHandler = @MainActor (String, CGImage?) async throws -> String

    private var panel: RecordingNotesPanel?
    private var model: RecordingNotesModel?
    private var onAssist: AssistHandler?
    private var assistTask: Task<Void, Never>?
    private var pendingAutomaticImage: CGImage?
    private var assistGeneration = 0

    func show(
        settingsManager: SettingsManager,
        onAssist: @escaping AssistHandler
    ) {
        let model = RecordingNotesModel(
            isAutoAssistEnabled: settingsManager.preferredProvider != .none
        )
        self.model = model
        self.onAssist = onAssist
        let panel = RecordingNotesPanel(
            content: RecordingNotesView(
                model: model,
                settingsManager: settingsManager,
                onManualAssist: { [weak self] in
                    self?.requestManualAssist()
                }
            )
        )

        if let screen = preferredPresentationScreen {
            let frame = screen.visibleFrame
            let margin: CGFloat = 24
            panel.setFrameOrigin(
                NSPoint(x: frame.maxX - panel.frame.width - margin, y: frame.maxY - panel.frame.height - margin)
            )
        } else {
            panel.center()
        }

        self.panel = panel
        present(panel)

        // Activation-policy and Space changes settle on the next run-loop turn.
        // Re-ordering once prevents a new panel from being left behind a full-screen
        // presentation or the quick-record palette.
        Task { @MainActor [weak self, weak panel] in
            await Task.yield()
            guard let self, let panel, self.panel === panel else { return }
            self.present(panel)
        }
    }

    private var preferredPresentationScreen: NSScreen? {
        let mouseLocation = NSEvent.mouseLocation
        return NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) })
            ?? NSApplication.shared.keyWindow?.screen
            ?? NSScreen.main
    }

    private func present(_ panel: NSPanel) {
        NSApplication.shared.activate()
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()
    }

    func requestAutomaticAssist(image: CGImage) {
        guard model?.isAutoAssistEnabled == true else { return }
        guard assistTask == nil else {
            // The newest relevant frame is the most useful follow-up context.
            pendingAutomaticImage = image
            return
        }
        runAssist(sourceImage: image)
    }

    private func requestManualAssist() {
        guard assistTask == nil else { return }
        runAssist(sourceImage: nil)
    }

    private func runAssist(sourceImage: CGImage?) {
        guard let model, let onAssist else { return }
        assistGeneration += 1
        let generation = assistGeneration
        model.isAssisting = true
        model.assistError = nil
        let notes = model.text

        assistTask = Task { [weak self] in
            do {
                let response = try await onAssist(notes, sourceImage)
                try Task.checkCancellation()
                guard let self, self.assistGeneration == generation else { return }
                self.model?.assistResponse = response
            } catch is CancellationError {
                // Recording stopped or the notes panel was dismissed.
            } catch {
                guard let self, self.assistGeneration == generation else { return }
                self.model?.assistError = error.localizedDescription
            }

            guard let self, self.assistGeneration == generation else { return }
            self.model?.isAssisting = false
            self.assistTask = nil

            if let pendingImage = self.pendingAutomaticImage,
               self.model?.isAutoAssistEnabled == true {
                self.pendingAutomaticImage = nil
                self.runAssist(sourceImage: pendingImage)
            } else {
                self.pendingAutomaticImage = nil
            }
        }
    }

    func stop() -> String {
        let notes = model?.text.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        assistGeneration += 1
        assistTask?.cancel()
        assistTask = nil
        pendingAutomaticImage = nil
        onAssist = nil
        panel?.close()
        panel = nil
        model = nil
        return notes
    }
}

private struct RecordingNotesView: View {
    @Bindable var model: RecordingNotesModel
    @Bindable var settingsManager: SettingsManager
    let onManualAssist: @MainActor () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Circle()
                    .fill(MapleTheme.error)
                    .frame(width: 8, height: 8)
                Text("Recording")
                    .font(.headline)
                    .foregroundStyle(MapleTheme.textPrimary)
                Spacer()

                Toggle(isOn: $model.isAutoAssistEnabled) {
                    Label("Assist", systemImage: "sparkles")
                }
                .toggleStyle(.switch)
                .controlSize(.small)
                .disabled(settingsManager.preferredProvider == .none)
                .help(assistHelp)

                Button {
                    onManualAssist()
                } label: {
                    if model.isAssisting {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(model.isAssisting || settingsManager.preferredProvider == .none)
                .help("Analyze the current screen now")
            }

            VSplitView {
                assistResponseSection
                    .frame(minHeight: 110, idealHeight: 210)

                notepadSection
                    .frame(minHeight: 120, idealHeight: 230)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            HStack {
                Label("Share a window to keep notes private", systemImage: "rectangle.on.rectangle.slash")
                Spacer()
                Text(assistContextLabel)
            }
            .font(.caption)
            .foregroundStyle(MapleTheme.textSecondary)
        }
        .padding(16)
        .background(MapleTheme.background)
        .frame(minWidth: 300, minHeight: 300)
    }

    private var assistResponseSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("AI Response", systemImage: "quote.bubble.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(MapleTheme.primary)
                Spacer()

                if !model.assistResponse.isEmpty {
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(model.assistResponse, forType: .string)
                    } label: {
                        Image(systemName: "doc.on.doc")
                    }
                    .buttonStyle(.plain)
                    .help("Copy answer")

                    Button("Add to notes") {
                        let heading = "Suggested answer:"
                        if model.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            model.text = "\(heading)\n\(model.assistResponse)"
                        } else {
                            model.text += "\n\n\(heading)\n\(model.assistResponse)"
                        }
                    }
                    .font(.caption)
                    .buttonStyle(.plain)
                    .foregroundStyle(MapleTheme.primary)
                }
            }

            Group {
                if model.isAssisting {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Reading the changed screen and drafting an answer…")
                            .font(.caption)
                            .foregroundStyle(MapleTheme.textSecondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                } else if let error = model.assistError {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(MapleTheme.error)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                } else if model.assistResponse.isEmpty {
                    ContentUnavailableView(
                        "Waiting for a screen change",
                        systemImage: "sparkles.rectangle.stack",
                        description: Text("Assist will place its suggested response here.")
                    )
                } else {
                    ScrollView {
                        Text(model.assistResponse)
                            .font(.body)
                            .foregroundStyle(MapleTheme.textPrimary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(10)
        .background(MapleTheme.primaryLight.opacity(0.35), in: .rect(cornerRadius: 10))
    }

    private var notepadSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Notepad", systemImage: "square.and.pencil")
                .font(.caption.weight(.semibold))
                .foregroundStyle(MapleTheme.textSecondary)

            TextEditor(text: $model.text)
                .font(.body)
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(MapleTheme.surfaceAlt, in: .rect(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(MapleTheme.border.opacity(0.35), lineWidth: 1)
                )
        }
        .padding(.top, 8)
    }

    private var assistHelp: String {
        settingsManager.preferredProvider == .none
            ? "Choose an AI provider in Settings first"
            : "Read the visible presentation and suggest a Q&A response"
    }

    private var assistContextLabel: String {
        let provider = settingsManager.preferredProvider
        let sendsImage = (provider == .claude || provider == .openai)
            && settingsManager.shareAssistScreenshotsWithCloudAI
        let mode = model.isAutoAssistEnabled ? "Auto" : "Paused"
        return "\(mode) · \(provider.displayName) · \(sendsImage ? "image + OCR" : "OCR")"
    }
}

// MARK: - Focused-window screenshots

private struct AssistScreenContext {
    let recognizedText: String
    let image: LLMImage?
}

@MainActor
private final class FocusedWindowScreenshotCapture {
    private static let captureInterval: TimeInterval = 5
    private static let fingerprintSide = 32

    var onWarning: ((String) -> Void)?
    var onRelevantFrame: ((CGImage) -> Void)?

    private var timer: Timer?
    private var captureTask: Task<Void, Never>?
    private var activationObserver: NSObjectProtocol?
    private var recordingID: UUID?
    private var startedAt: Date?
    private var targetPID: pid_t?
    private var screenshots: [CapturedTimelineScreenshot] = []
    private var lastFingerprint: [UInt8]?
    private var lastWindowID: CGWindowID?
    private var hasReportedFailure = false

    func start(recordingID: UUID, initialTargetPID: pid_t?) {
        stopWithoutResults()
        self.recordingID = recordingID
        self.startedAt = Date()
        self.targetPID = initialTargetPID

        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  application.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
            let pid = application.processIdentifier
            Task { @MainActor [weak self] in self?.targetPID = pid }
        }

        captureNow()
        timer = Timer.scheduledTimer(withTimeInterval: Self.captureInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.captureNow() }
        }
    }

    func stop() -> [CapturedTimelineScreenshot] {
        timer?.invalidate()
        timer = nil
        captureTask?.cancel()
        captureTask = nil
        removeActivationObserver()

        let result = screenshots.sorted { $0.timestamp < $1.timestamp }
        recordingID = nil
        startedAt = nil
        targetPID = nil
        screenshots = []
        lastFingerprint = nil
        lastWindowID = nil
        hasReportedFailure = false
        return result
    }

    private func stopWithoutResults() {
        timer?.invalidate()
        captureTask?.cancel()
        removeActivationObserver()
        timer = nil
        captureTask = nil
        screenshots = []
        lastFingerprint = nil
        lastWindowID = nil
        hasReportedFailure = false
    }

    private func removeActivationObserver() {
        if let activationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(activationObserver)
            self.activationObserver = nil
        }
    }

    private func captureNow() {
        guard captureTask == nil,
              let recordingID,
              let startedAt,
              let targetPID else { return }

        let timestamp = max(0, Date().timeIntervalSince(startedAt))
        captureTask = Task { [weak self] in
            guard let self else { return }
            defer { self.captureTask = nil }

            do {
                let (image, windowID) = try await self.captureImage(for: targetPID)
                try Task.checkCancellation()

                let fingerprint = Self.fingerprint(for: image)
                guard VisualFrameDiffer.isMeaningfullyDifferent(
                    fingerprint,
                    from: self.lastFingerprint,
                    windowChanged: self.lastWindowID != windowID
                ) else { return }

                let sequence = self.screenshots.count + 1
                let fileName = "\(recordingID.uuidString)-screen-\(String(format: "%04d", sequence)).jpg"
                let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
                try Self.writeJPEG(image, to: url)
                try Task.checkCancellation()

                self.lastFingerprint = fingerprint
                self.lastWindowID = windowID
                self.screenshots.append(CapturedTimelineScreenshot(sourceURL: url, timestamp: timestamp))
                self.onRelevantFrame?(image)
            } catch is CancellationError {
                return
            } catch {
                guard !self.hasReportedFailure else { return }
                self.hasReportedFailure = true
                self.onWarning?("Screenshots unavailable: \(error.localizedDescription)")
            }
        }
    }

    func assistContext(from sourceImage: CGImage?, includeImage: Bool) async throws -> AssistScreenContext {
        let image: CGImage
        if let sourceImage {
            image = sourceImage
        } else {
            guard let targetPID else { throw ScreenshotCaptureError.noFocusedWindow }
            let captured = try await captureImage(for: targetPID)
            image = captured.0
        }

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])

        let text = (request.results ?? [])
            .sorted {
                if abs($0.boundingBox.midY - $1.boundingBox.midY) > 0.015 {
                    return $0.boundingBox.midY > $1.boundingBox.midY
                }
                return $0.boundingBox.minX < $1.boundingBox.minX
            }
            .compactMap { $0.topCandidates(1).first?.string }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !text.isEmpty || includeImage else { throw ScreenshotCaptureError.noReadableText }
        let recognizedText = text.isEmpty
            ? "No readable text was detected; use the attached screen image."
            : text
        let llmImage = includeImage
            ? LLMImage(data: try Self.jpegData(image), mediaType: "image/jpeg")
            : nil
        return AssistScreenContext(recognizedText: recognizedText, image: llmImage)
    }

    private func captureImage(for pid: pid_t) async throws -> (CGImage, CGWindowID) {
        let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
        try Task.checkCancellation()
        guard let window = Self.bestWindow(in: content.windows, ownedBy: pid) else {
            throw ScreenshotCaptureError.noFocusedWindow
        }

        let filter = SCContentFilter(desktopIndependentWindow: window)
        let configuration = SCStreamConfiguration()
        let scale = max(CGFloat(filter.pointPixelScale), 1)
        let sourceWidth = max(window.frame.width * scale, 1)
        let sourceHeight = max(window.frame.height * scale, 1)
        let outputScale = min(1, 1600 / sourceWidth)
        configuration.width = Int(sourceWidth * outputScale)
        configuration.height = Int(sourceHeight * outputScale)
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        configuration.showsCursor = false
        configuration.ignoreShadowsSingleWindow = true

        let image = try await SCScreenshotManager.captureImage(
            contentFilter: filter,
            configuration: configuration
        )
        return (image, window.windowID)
    }

    /// ScreenCaptureKit supplies shareable windows, while CoreGraphics supplies their
    /// front-to-back order. Matching the two gives us the focused content window rather
    /// than an arbitrary utility palette from the same presentation app.
    private static func bestWindow(in windows: [SCWindow], ownedBy pid: pid_t) -> SCWindow? {
        let candidates = windows.filter {
            $0.owningApplication?.processID == pid
                && $0.isOnScreen
                && $0.windowLayer == 0
                && $0.frame.width >= 320
                && $0.frame.height >= 180
        }
        guard !candidates.isEmpty else { return nil }

        if let windowInfo = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[CFString: Any]] {
            for info in windowInfo {
                guard let ownerPID = info[kCGWindowOwnerPID] as? Int, ownerPID == Int(pid),
                      let windowNumber = info[kCGWindowNumber] as? CGWindowID,
                      let match = candidates.first(where: { $0.windowID == windowNumber }) else { continue }
                return match
            }
        }

        return candidates.max { lhs, rhs in
            lhs.frame.width * lhs.frame.height < rhs.frame.width * rhs.frame.height
        }
    }

    private static func fingerprint(for image: CGImage) -> [UInt8] {
        let side = fingerprintSide
        var pixels = [UInt8](repeating: 0, count: side * side)
        guard let colorSpace = CGColorSpace(name: CGColorSpace.linearGray),
              let context = CGContext(
                data: &pixels,
                width: side,
                height: side,
                bitsPerComponent: 8,
                bytesPerRow: side,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.none.rawValue
              ) else { return pixels }

        context.interpolationQuality = .medium
        context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
        return pixels
    }

    private static func writeJPEG(_ image: CGImage, to url: URL) throws {
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else {
            throw ScreenshotCaptureError.cannotCreateImage
        }

        CGImageDestinationAddImage(
            destination,
            image,
            [kCGImageDestinationLossyCompressionQuality: 0.78] as CFDictionary
        )
        guard CGImageDestinationFinalize(destination) else {
            throw ScreenshotCaptureError.cannotWriteImage
        }
    }

    private static func jpegData(_ image: CGImage) throws -> Data {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else {
            throw ScreenshotCaptureError.cannotCreateImage
        }

        CGImageDestinationAddImage(
            destination,
            image,
            [kCGImageDestinationLossyCompressionQuality: 0.72] as CFDictionary
        )
        guard CGImageDestinationFinalize(destination) else {
            throw ScreenshotCaptureError.cannotWriteImage
        }
        return data as Data
    }
}

private enum ScreenshotCaptureError: LocalizedError {
    case cannotCreateImage
    case cannotWriteImage
    case noFocusedWindow
    case noReadableText

    var errorDescription: String? {
        switch self {
        case .cannotCreateImage: "Could not create the screenshot file."
        case .cannotWriteImage: "Could not save the screenshot file."
        case .noFocusedWindow: "Switch to the presentation window once, then try Assist again."
        case .noReadableText: "No readable text was found in the presentation window."
        }
    }
}
#endif
