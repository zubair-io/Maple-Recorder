# Camera Video Recording Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let users record themselves on camera (iOS + macOS) alongside the existing audio recording, with a live preview, a chip-style toggle matching the restyled "system audio" control, playback in the recording detail view, and a Settings camera picker.

**Architecture:** A new, independent `VideoRecorder` (`AVCaptureSession` + `AVCaptureMovieFileOutput`, video-only) lives alongside the existing `AudioRecorder` and is coordinated at the `RecordingListView` level — it does not touch the audio/transcription pipeline. Video is saved as `{uuid}.mov`, sibling to the existing `{uuid}.md`/`{uuid}.m4a` pair, tracked explicitly via a new `videoFile` field on `MapleRecording` (mirroring how `audioFiles`/`systemAudioFiles` are already tracked).

**Tech Stack:** Swift, SwiftUI, AVFoundation (`AVCaptureSession`, `AVCaptureDevice`, `AVCaptureMovieFileOutput`, `AVCaptureVideoPreviewLayer`), AVKit (`VideoPlayer`), Swift Testing (`@Test`/`#expect`).

## Global Constraints

- No video chunking/segmentation — one continuous `.mov` file per recording (video doesn't feed ASR).
- No inline camera-picker menu on the record FAB — camera device selection lives in Settings only.
- No watchOS support — every new file/branch touching `AVCaptureSession`/`AVCaptureDevice` must be excluded from watchOS compilation (`#if !os(watchOS)` at the top of the file, or the file's platform branches naturally exclude it).
- No support in `QuickRecordPanel`/`QuickRecordController` — camera UI only appears in `RecordingListView`'s main recording flow.
- No use of the video track's pixels or audio for transcription/diarization.
- All new `FileManager` path lookups MUST use `path(percentEncoded: false)`, never bare `path()` — the iCloud container path contains a space that `path()` percent-encodes, breaking `fileExists(atPath:)` on macOS (see `Maple RecorderTests/Storage/RecordingStoreTests.swift:75` for the regression this guards against).
- Default camera: **front camera on iOS**, **first built-in camera on macOS** (used when `preferredCameraID` is unset).
- Reference spec: `docs/superpowers/specs/2026-08-04-camera-video-recording-design.md`.

---

### Task 1: `MapleRecording` gains a `videoFile` field

**Files:**
- Modify: `Maple Recorder/Models/MapleRecording.swift`
- Test: `Maple RecorderTests/Models/MapleRecordingTests.swift`

**Interfaces:**
- Produces: `MapleRecording.videoFile: String?` (filename only, relative to `StorageLocation.recordingsURL`), `MapleRecording.MetadataJSON.video: String?`.

- [ ] **Step 1: Write the failing tests**

Add to `Maple RecorderTests/Models/MapleRecordingTests.swift` (inside `struct MapleRecordingTests`, after `emptyTranscriptEncoding`):

```swift
    @Test func videoFileRoundTrip() throws {
        let date = Date(timeIntervalSince1970: 1700000000)
        var recording = MapleRecording(
            title: "Test Recording",
            audioFiles: ["test.m4a"],
            duration: 60.0,
            createdAt: date,
            modifiedAt: date
        )
        recording.videoFile = "test.mov"

        let encoder = makeEncoder()
        let data = try encoder.encode(recording.metadata)

        let decoder = makeDecoder()
        let decoded = try decoder.decode(MapleRecording.MetadataJSON.self, from: data)

        #expect(decoded.video == "test.mov")

        let rebuilt = MapleRecording(title: recording.title, summary: recording.summary, metadata: decoded)
        #expect(rebuilt.videoFile == "test.mov")
    }

    @Test func decodingMetadataWithoutVideoFieldDefaultsToNil() throws {
        let json = """
        {"id":"\\(UUID().uuidString)","audio":["a.m4a"],"duration":1,"created_at":"2023-11-14T22:13:20Z","modified_at":"2023-11-14T22:13:20Z","speakers":[],"transcript":[],"prompt_results":[],"tags":[]}
        """
        let decoder = makeDecoder()
        let decoded = try decoder.decode(MapleRecording.MetadataJSON.self, from: Data(json.utf8))
        #expect(decoded.video == nil)
    }

    @Test func defaultVideoFileIsNil() {
        let recording = MapleRecording(title: "Untitled")
        #expect(recording.videoFile == nil)
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild -project "Maple Recorder.xcodeproj" -scheme "Maple Recorder" -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:"Maple RecorderTests/MapleRecordingTests" test`
Expected: FAIL — `value of type 'MapleRecording' has no member 'videoFile'` / `value of type 'MapleRecording.MetadataJSON' has no member 'video'`

- [ ] **Step 3: Implement — add `videoFile` to `MapleRecording`**

In `Maple Recorder/Models/MapleRecording.swift`, add the field to the struct (right after `systemAudioFiles`):

```swift
    var audioFiles: [String]
    var systemAudioFiles: [String]
    var videoFile: String?
```

Add the parameter to `init` (right after `systemAudioFiles: [String] = []`), and assign it in the body:

```swift
        systemAudioFiles: [String] = [],
        videoFile: String? = nil,
```
```swift
        self.systemAudioFiles = systemAudioFiles
        self.videoFile = videoFile
```

- [ ] **Step 4: Implement — add `video` to `MetadataJSON`**

In the same file's `MetadataJSON` struct, add the field (after `systemAudio`):

```swift
        var systemAudio: [String]
        var video: String?
```

Add to `CodingKeys` (the plain-name group already includes `id, audio, duration, speakers, transcript, tags` — add `video` there):

```swift
        enum CodingKeys: String, CodingKey {
            case id, audio, video, duration, speakers, transcript, tags
            case systemAudio = "system_audio"
            case createdAt = "created_at"
            case modifiedAt = "modified_at"
            case promptResults = "prompt_results"
        }
```

Add the parameter to `MetadataJSON.init(...)` (after `systemAudio: [String] = []`), and assign it:

```swift
            systemAudio: [String] = [],
            video: String? = nil,
```
```swift
            self.systemAudio = systemAudio
            self.video = video
```

Add to `init(from decoder:)` (after the `systemAudio` line):

```swift
            systemAudio = try container.decodeIfPresent([String].self, forKey: .systemAudio) ?? []
            video = try container.decodeIfPresent(String.self, forKey: .video)
```

- [ ] **Step 5: Implement — wire `videoFile` through `metadata` and the metadata-based initializer**

In the `metadata` computed property, add:

```swift
    var metadata: MetadataJSON {
        MetadataJSON(
            id: id,
            audio: audioFiles,
            systemAudio: systemAudioFiles,
            video: videoFile,
            duration: duration,
```

In `init(title:summary:metadata:)`, add:

```swift
        self.systemAudioFiles = metadata.systemAudio
        self.videoFile = metadata.video
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `xcodebuild -project "Maple Recorder.xcodeproj" -scheme "Maple Recorder" -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:"Maple RecorderTests/MapleRecordingTests" test`
Expected: PASS (all `MapleRecordingTests`, including the 3 new tests and the pre-existing ones)

- [ ] **Step 7: Commit**

```bash
git add "Maple Recorder/Models/MapleRecording.swift" "Maple RecorderTests/Models/MapleRecordingTests.swift"
git commit -m "feat: add videoFile field to MapleRecording"
```

---

### Task 2: `RecordingStore.delete()` removes the video file

**Files:**
- Modify: `Maple Recorder/Storage/RecordingStore.swift:135-157` (the `delete(_:)` method)
- Test: `Maple RecorderTests/Storage/RecordingStoreTests.swift`

**Interfaces:**
- Consumes: `MapleRecording.videoFile: String?` (Task 1).

- [ ] **Step 1: Write the failing test**

Add to `Maple RecorderTests/Storage/RecordingStoreTests.swift` (inside `struct RecordingStoreTests`, after `deleteRemovesFile`):

```swift
    @Test func deleteRemovesVideoFile() throws {
        let dir = try makeTempDirectory()
        defer { cleanup(dir) }

        let store = RecordingStore(directory: dir)
        var recording = MapleRecording(
            title: "With Video",
            audioFiles: ["clip.m4a"],
            duration: 10.0
        )
        recording.videoFile = "clip.mov"

        // Store.save only writes the .md file; create the sibling audio/video
        // files directly so delete() has something real to remove.
        try Data().write(to: dir.appendingPathComponent("clip.m4a"))
        try Data().write(to: dir.appendingPathComponent("clip.mov"))

        try store.save(recording)
        try store.delete(recording)

        let videoPath = dir.appendingPathComponent("clip.mov").path(percentEncoded: false)
        #expect(!FileManager.default.fileExists(atPath: videoPath))
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild -project "Maple Recorder.xcodeproj" -scheme "Maple Recorder" -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:"Maple RecorderTests/RecordingStoreTests/deleteRemovesVideoFile" test`
Expected: FAIL — the `.mov` file is never removed by `delete()`, so `fileExists` is still `true`.

- [ ] **Step 3: Implement**

In `Maple Recorder/Storage/RecordingStore.swift`, in `delete(_:)`, add after the `systemAudioFiles` removal loop (after line 153, before `recordings.removeAll`):

```swift
        for audioFile in recording.systemAudioFiles {
            let audioURL = recordingsURL.appendingPathComponent(audioFile)
            if fileManager.fileExists(atPath: audioURL.path(percentEncoded: false)) {
                try fileManager.removeItem(at: audioURL)
            }
        }

        if let videoFile = recording.videoFile {
            let videoURL = recordingsURL.appendingPathComponent(videoFile)
            if fileManager.fileExists(atPath: videoURL.path(percentEncoded: false)) {
                try fileManager.removeItem(at: videoURL)
            }
        }

        recordings.removeAll { $0.id == recording.id }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild -project "Maple Recorder.xcodeproj" -scheme "Maple Recorder" -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:"Maple RecorderTests/RecordingStoreTests" test`
Expected: PASS (all `RecordingStoreTests`, including the new test)

- [ ] **Step 5: Commit**

```bash
git add "Maple Recorder/Storage/RecordingStore.swift" "Maple RecorderTests/Storage/RecordingStoreTests.swift"
git commit -m "feat: delete video file when a recording is deleted"
```

---

### Task 3: `preferredCameraID` setting

**Files:**
- Modify: `Maple Recorder/Models/AppSettings.swift`
- Modify: `Maple Recorder/ML/SettingsManager.swift`
- Test: Create `Maple RecorderTests/Models/AppSettingsTests.swift`

**Interfaces:**
- Produces: `AppSettings.preferredCameraID: String?`, `SettingsManager.preferredCameraID: String?` (get/set, persists via `save()`).

- [ ] **Step 1: Write the failing tests**

Create `Maple RecorderTests/Models/AppSettingsTests.swift`:

```swift
import Testing
import Foundation
@testable import Maple_Recorder

struct AppSettingsTests {

    @Test func preferredCameraIDDefaultsToNil() {
        let settings = AppSettings(preferredLLMProvider: .none)
        #expect(settings.preferredCameraID == nil)
    }

    @Test func preferredCameraIDRoundTrip() throws {
        var settings = AppSettings(preferredLLMProvider: .none)
        settings.preferredCameraID = "com.apple.avfoundation.avcapturedevice.built-in_video:0"

        let encoder = JSONEncoder()
        let data = try encoder.encode(settings)

        let decoded = try JSONDecoder().decode(AppSettings.self, from: data)
        #expect(decoded.preferredCameraID == "com.apple.avfoundation.avcapturedevice.built-in_video:0")
    }

    @Test func decodingSettingsWithoutCameraFieldDefaultsToNil() throws {
        let json = """
        {"preferred_llm_provider":"none","icloud_enabled":true,"chunk_duration_minutes":30}
        """
        let decoded = try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))
        #expect(decoded.preferredCameraID == nil)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild -project "Maple Recorder.xcodeproj" -scheme "Maple Recorder" -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:"Maple RecorderTests/AppSettingsTests" test`
Expected: FAIL — `value of type 'AppSettings' has no member 'preferredCameraID'`

- [ ] **Step 3: Implement — add the field to `AppSettings`**

In `Maple Recorder/Models/AppSettings.swift`, add the property (after `selectedCalendarIdentifiers`):

```swift
    var selectedCalendarIdentifiers: [String]  // empty = all calendars

    // Camera
    var preferredCameraID: String?  // AVCaptureDevice.uniqueID; nil = use platform default
```

Add to `CodingKeys`:

```swift
        case selectedCalendarIdentifiers = "selected_calendar_identifiers"
        case preferredCameraID = "preferred_camera_id"
```

Add to the memberwise `init` (parameter + assignment, after `selectedCalendarIdentifiers: [String] = []`):

```swift
        selectedCalendarIdentifiers: [String] = [],
        preferredCameraID: String? = nil
```
```swift
        self.selectedCalendarIdentifiers = selectedCalendarIdentifiers
        self.preferredCameraID = preferredCameraID
```

Add to `init(from decoder:)` (after the `selectedCalendarIdentifiers` migration block):

```swift
        preferredCameraID = try container.decodeIfPresent(String.self, forKey: .preferredCameraID)
```

- [ ] **Step 4: Implement — add the computed property to `SettingsManager`**

In `Maple Recorder/ML/SettingsManager.swift`, add after `selectedCalendarIdentifiers` (before `// MARK: - Persistence`):

```swift
    // MARK: - Camera Settings

    var preferredCameraID: String? {
        get { settings.preferredCameraID }
        set {
            settings.preferredCameraID = newValue
            try? save()
        }
    }
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `xcodebuild -project "Maple Recorder.xcodeproj" -scheme "Maple Recorder" -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:"Maple RecorderTests/AppSettingsTests" test`
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add "Maple Recorder/Models/AppSettings.swift" "Maple Recorder/ML/SettingsManager.swift" "Maple RecorderTests/Models/AppSettingsTests.swift"
git commit -m "feat: add preferredCameraID setting"
```

---

### Task 4: Camera permission — Info.plist + macOS entitlement

**Files:**
- Modify: `Maple Recorder/Info.plist`
- Modify: `Maple Recorder/Maple Recorder.entitlements`

**Interfaces:**
- None (build configuration only — no Swift symbols produced or consumed).

- [ ] **Step 1: Add `NSCameraUsageDescription` to Info.plist**

In `Maple Recorder/Info.plist`, add after the `NSMicrophoneUsageDescription` entry (after line 13):

```xml
	<key>NSCameraUsageDescription</key>
	<string>Maple Recorder needs camera access to record video alongside your audio.</string>
```

- [ ] **Step 2: Add the camera device entitlement**

In `Maple Recorder/Maple Recorder.entitlements`, add a new key inside the top-level `<dict>` (order doesn't matter; add it anywhere inside the existing `<dict>...</dict>`):

```xml
	<key>com.apple.security.device.camera</key>
	<true/>
```

- [ ] **Step 3: Build to verify no regressions**

Run: `xcodebuild -project "Maple Recorder.xcodeproj" -scheme "Maple Recorder" -destination 'platform=macOS' build`
Expected: BUILD SUCCEEDED. (This task adds no camera-consuming code yet — it only needs to not break the existing build. If the macOS build fails specifically due to the new entitlement key, e.g. an unrecognized-entitlement provisioning error, note it here and continue — Task 9's manual verification is where actual camera access on macOS gets exercised end-to-end.)

- [ ] **Step 4: Commit**

```bash
git add "Maple Recorder/Info.plist" "Maple Recorder/Maple Recorder.entitlements"
git commit -m "feat: add camera usage description and entitlement"
```

---

### Task 5: `VideoRecorder` capture engine

**Files:**
- Create: `Maple Recorder/Video/VideoRecorder.swift`

**Interfaces:**
- Consumes: nothing from earlier tasks.
- Produces:
  - `final class VideoRecorder: NSObject` (`@Observable`, `#if !os(watchOS)`-only)
  - `var isSessionRunning: Bool` (read-only from outside)
  - `var captureError: String?` (settable)
  - `var permissionGranted: Bool`
  - `let session: AVCaptureSession`
  - `func requestPermissionIfNeeded() async -> Bool`
  - `func startSession(preferredDeviceID: String?)`
  - `func stopSession()`
  - `func startRecording(id: UUID)`
  - `func stopRecording() async -> URL?` (returns the temp file URL, or `nil` if nothing was recording)
  - `static func availableDevices() -> [AVCaptureDevice]`

This is a hardware-capture class — not meaningfully unit-testable without a physical/simulated camera. No automated test for this task; Task 9's manual simulator/device verification exercises it end-to-end.

- [ ] **Step 1: Create the file**

Create `Maple Recorder/Video/VideoRecorder.swift`:

```swift
#if !os(watchOS)
import AVFoundation
import Foundation
import Observation

@Observable
final class VideoRecorder: NSObject {
    private(set) var isSessionRunning = false
    var permissionGranted = false
    var captureError: String?

    let session = AVCaptureSession()

    private let movieOutput = AVCaptureMovieFileOutput()
    private var deviceInput: AVCaptureDeviceInput?
    private let sessionQueue = DispatchQueue(label: "com.maple.videoCapture")
    private var recordingCompletion: CheckedContinuation<URL?, Never>?

    override init() {
        super.init()
        session.sessionPreset = .high
        if session.canAddOutput(movieOutput) {
            session.addOutput(movieOutput)
        }
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleRuntimeError(_:)),
            name: .AVCaptureSessionRuntimeError,
            object: session
        )
    }

    func requestPermissionIfNeeded() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            permissionGranted = true
            return true
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            permissionGranted = granted
            return granted
        default:
            permissionGranted = false
            return false
        }
    }

    func startSession(preferredDeviceID: String?) {
        guard let device = Self.resolveDevice(preferredID: preferredDeviceID) else {
            captureError = "No camera available."
            return
        }
        sessionQueue.async { [weak self] in
            guard let self else { return }
            do {
                let input = try AVCaptureDeviceInput(device: device)
                self.session.beginConfiguration()
                if let existing = self.deviceInput {
                    self.session.removeInput(existing)
                }
                if self.session.canAddInput(input) {
                    self.session.addInput(input)
                    self.deviceInput = input
                }
                self.session.commitConfiguration()
                self.session.startRunning()
                let isRunning = self.session.isRunning
                Task { @MainActor in
                    self.isSessionRunning = isRunning
                    self.captureError = nil
                }
            } catch {
                let description = error.localizedDescription
                Task { @MainActor in
                    self.captureError = description
                }
            }
        }
    }

    func stopSession() {
        sessionQueue.async { [weak self] in
            self?.session.stopRunning()
            Task { @MainActor in
                self?.isSessionRunning = false
            }
        }
    }

    func startRecording(id: UUID) {
        let tempDir = FileManager.default.temporaryDirectory
        let url = tempDir.appendingPathComponent("\(id.uuidString).mov")
        if FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) {
            try? FileManager.default.removeItem(at: url)
        }
        movieOutput.startRecording(to: url, recordingDelegate: self)
    }

    func stopRecording() async -> URL? {
        guard movieOutput.isRecording else { return nil }
        return await withCheckedContinuation { continuation in
            self.recordingCompletion = continuation
            movieOutput.stopRecording()
        }
    }

    @objc private func handleRuntimeError(_ notification: Notification) {
        let description = (notification.userInfo?[AVCaptureSessionErrorKey] as? Error)?.localizedDescription
            ?? "Camera stopped unexpectedly."
        Task { @MainActor in
            self.isSessionRunning = false
            self.captureError = description
        }
    }

    private static func resolveDevice(preferredID: String?) -> AVCaptureDevice? {
        if let preferredID, let device = AVCaptureDevice(uniqueID: preferredID) {
            return device
        }
        #if os(iOS)
        return AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
            ?? AVCaptureDevice.default(for: .video)
        #else
        return AVCaptureDevice.default(for: .video)
        #endif
    }

    static func availableDevices() -> [AVCaptureDevice] {
        #if os(iOS)
        let types: [AVCaptureDevice.DeviceType] = [.builtInWideAngleCamera, .builtInDualCamera, .builtInTrueDepthCamera]
        #else
        let types: [AVCaptureDevice.DeviceType] = [.builtInWideAngleCamera, .external, .continuityCamera]
        #endif
        return AVCaptureDevice.DiscoverySession(deviceTypes: types, mediaType: .video, position: .unspecified).devices
    }
}

extension VideoRecorder: AVCaptureFileOutputRecordingDelegate {
    func fileOutput(
        _ output: AVCaptureFileOutput,
        didFinishRecordingTo outputFileURL: URL,
        from connections: [AVCaptureConnection],
        error: (any Error)?
    ) {
        let result: URL? = error == nil ? outputFileURL : nil
        Task { @MainActor in
            self.recordingCompletion?.resume(returning: result)
            self.recordingCompletion = nil
        }
    }
}
#endif
```

- [ ] **Step 2: Build to verify it compiles on both platforms**

Run: `xcodebuild -project "Maple Recorder.xcodeproj" -scheme "Maple Recorder" -destination 'platform=iOS Simulator,name=iPhone 16' build`
Run: `xcodebuild -project "Maple Recorder.xcodeproj" -scheme "Maple Recorder" -destination 'platform=macOS' build`
Run: `xcodebuild -project "Maple Recorder.xcodeproj" -scheme "Maple Recorder Watch App" -destination 'platform=watchOS Simulator,name=Apple Watch Series 10 (46mm)' build`
Expected: BUILD SUCCEEDED for all three (the watchOS build must succeed with `VideoRecorder` compiled out entirely).

- [ ] **Step 3: Commit**

```bash
git add "Maple Recorder/Video/VideoRecorder.swift"
git commit -m "feat: add VideoRecorder capture engine"
```

---

### Task 6: `CameraPreviewView`

**Files:**
- Create: `Maple Recorder/Video/CameraPreviewView.swift`

**Interfaces:**
- Consumes: `VideoRecorder.session: AVCaptureSession` (Task 5) — passed in directly, no dependency on the class itself.
- Produces: `struct CameraPreviewView` (`UIViewRepresentable` on iOS, `NSViewRepresentable` on macOS) with `init(session: AVCaptureSession)`.

Not unit-testable (renders a live camera feed) — verified visually in Task 9.

- [ ] **Step 1: Create the file**

Create `Maple Recorder/Video/CameraPreviewView.swift`:

```swift
import AVFoundation
import SwiftUI

#if os(iOS)
import UIKit

struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewUIView {
        let view = PreviewUIView()
        view.videoPreviewLayer.session = session
        view.videoPreviewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewUIView, context: Context) {}

    final class PreviewUIView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var videoPreviewLayer: AVCaptureVideoPreviewLayer {
            // swiftlint:disable:next force_cast
            layer as! AVCaptureVideoPreviewLayer
        }
    }
}
#elseif os(macOS)
import AppKit

struct CameraPreviewView: NSViewRepresentable {
    let session: AVCaptureSession

    func makeNSView(context: Context) -> PreviewNSView {
        let view = PreviewNSView()
        view.videoPreviewLayer.session = session
        view.videoPreviewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateNSView(_ nsView: PreviewNSView, context: Context) {}

    final class PreviewNSView: NSView {
        let videoPreviewLayer = AVCaptureVideoPreviewLayer()

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            wantsLayer = true
            layer = videoPreviewLayer
        }

        required init?(coder: NSCoder) {
            super.init(coder: coder)
            wantsLayer = true
            layer = videoPreviewLayer
        }
    }
}
#endif
```

- [ ] **Step 2: Build to verify it compiles**

Run: `xcodebuild -project "Maple Recorder.xcodeproj" -scheme "Maple Recorder" -destination 'platform=iOS Simulator,name=iPhone 16' build`
Run: `xcodebuild -project "Maple Recorder.xcodeproj" -scheme "Maple Recorder" -destination 'platform=macOS' build`
Expected: BUILD SUCCEEDED for both.

- [ ] **Step 3: Commit**

```bash
git add "Maple Recorder/Video/CameraPreviewView.swift"
git commit -m "feat: add CameraPreviewView"
```

---

### Task 7: `RecordingOptionChip` component

**Files:**
- Create: `Maple Recorder/Views/Components/RecordingOptionChip.swift`

**Interfaces:**
- Produces: `struct RecordingOptionChip: View`, `init(title: String, systemImage: String, isOn: Binding<Bool>)`.

Pure SwiftUI, no existing view-testing precedent in this codebase (no snapshot tests) — verified visually in Task 9.

- [ ] **Step 1: Create the file**

Create `Maple Recorder/Views/Components/RecordingOptionChip.swift`:

```swift
import SwiftUI

/// A pill-shaped toggle button used for opt-in recording options (system audio,
/// video). Replaces the platform-native `.checkbox` toggle style so options stay
/// visually consistent across macOS and iOS, since iOS has no equivalent native style.
struct RecordingOptionChip: View {
    let title: String
    let systemImage: String
    @Binding var isOn: Bool

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            Label(title, systemImage: systemImage)
                .font(.caption)
                .foregroundStyle(isOn ? .white : MapleTheme.textPrimary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(isOn ? MapleTheme.primary : MapleTheme.surfaceAlt, in: .capsule)
                .overlay {
                    if !isOn {
                        Capsule().stroke(MapleTheme.border, lineWidth: 1)
                    }
                }
        }
        .buttonStyle(.plain)
    }
}
```

- [ ] **Step 2: Build to verify it compiles**

Run: `xcodebuild -project "Maple Recorder.xcodeproj" -scheme "Maple Recorder" -destination 'platform=iOS Simulator,name=iPhone 16' build`
Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Commit**

```bash
git add "Maple Recorder/Views/Components/RecordingOptionChip.swift"
git commit -m "feat: add RecordingOptionChip component"
```

---

### Task 8: Settings — camera picker

**Files:**
- Modify: `Maple Recorder/Views/SettingsView.swift`

**Interfaces:**
- Consumes: `SettingsManager.preferredCameraID: String?` (Task 3), `VideoRecorder.availableDevices() -> [AVCaptureDevice]` (Task 5).

- [ ] **Step 1: Add the `AVFoundation` import**

In `Maple Recorder/Views/SettingsView.swift`, add the import (top of file, after `import EventKit`):

```swift
#if !os(watchOS)
import AVFoundation
import EventKit
import SwiftUI
```

- [ ] **Step 2: Add the camera picker to `recordingSection`**

Replace the `recordingSection` body (`Maple Recorder/Views/SettingsView.swift:148-156`):

```swift
    private var recordingSection: some View {
        SettingsCard {
            SettingsSectionHeader(icon: "mic", title: "Recording")

            Text("Audio is captured at 48 kHz / 128 kbps AAC.")
                .font(.caption)
                .foregroundStyle(MapleTheme.textSecondary)

            Picker(selection: $settingsManager.preferredCameraID) {
                Text("Default").tag(nil as String?)
                ForEach(VideoRecorder.availableDevices(), id: \.uniqueID) { device in
                    Text(device.localizedName).tag(device.uniqueID as String?)
                }
            } label: {
                Text("Camera")
            }
            .pickerStyle(.menu)
            .padding(.top, 4)
        }
    }
```

- [ ] **Step 3: Build to verify it compiles**

Run: `xcodebuild -project "Maple Recorder.xcodeproj" -scheme "Maple Recorder" -destination 'platform=iOS Simulator,name=iPhone 16' build`
Run: `xcodebuild -project "Maple Recorder.xcodeproj" -scheme "Maple Recorder" -destination 'platform=macOS' build`
Expected: BUILD SUCCEEDED for both.

- [ ] **Step 4: Commit**

```bash
git add "Maple Recorder/Views/SettingsView.swift"
git commit -m "feat: add camera picker to Settings"
```

---

### Task 9: Wire video recording into `RecordingListView`

**Files:**
- Modify: `Maple Recorder/Views/RecordingListView.swift`

**Interfaces:**
- Consumes: `VideoRecorder` (Task 5), `CameraPreviewView` (Task 6), `RecordingOptionChip` (Task 7), `SettingsManager.preferredCameraID` (Task 3), `MapleRecording.videoFile` (Task 1).

This task is UI + hardware wiring — not unit-testable. Verified manually via the iOS Simulator (Step 5) and a macOS build.

- [ ] **Step 1: Add state**

In `Maple Recorder/Views/RecordingListView.swift`, add new `@State` properties after `@State private var recorder = AudioRecorder()` (line 15):

```swift
    @State private var recorder = AudioRecorder()
    #if !os(watchOS)
    @State private var videoRecorder = VideoRecorder()
    @State private var isVideoEnabled = false
    #endif
```

- [ ] **Step 2: Replace the FAB's option controls and add the live preview**

Replace the `recordFAB` property (`Maple Recorder/Views/RecordingListView.swift:296-353`) in full:

```swift
    private var recordFAB: some View {
        VStack(spacing: 8) {
            #if !os(watchOS)
            if isVideoEnabled {
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
        let granted = await videoRecorder.requestPermissionIfNeeded()
        guard granted else {
            isVideoEnabled = false
            videoRecorder.captureError = "Camera access denied. Enable it in System Settings > Privacy > Camera."
            return
        }
        videoRecorder.startSession(preferredDeviceID: settingsManager.preferredCameraID)
    }
    #endif
```

- [ ] **Step 3: Start video capture when recording starts**

Replace `startRecording()` (`Maple Recorder/Views/RecordingListView.swift:357-371`):

```swift
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
```

- [ ] **Step 4: Save the video file when recording stops**

Replace `stopRecording()` (`Maple Recorder/Views/RecordingListView.swift:373-451`):

```swift
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
        videoRecorder.stopSession()
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
        guard let tempURL = await videoRecorder.stopRecording() else { return }
        let destURL = StorageLocation.recordingsURL.appendingPathComponent(tempURL.lastPathComponent)
        try? FileManager.default.copyItem(at: tempURL, to: destURL)

        guard var recording = store.recordings.first(where: { $0.id == recordingId }) else { return }
        recording.videoFile = destURL.lastPathComponent
        try? store.update(recording)
    }
    #endif
```

- [ ] **Step 5: Manual verification on iOS Simulator**

Build and run on the iOS Simulator (this app's camera-permission prompt and live preview require an actual run, not just a build):

```bash
xcodebuild -project "Maple Recorder.xcodeproj" -scheme "Maple Recorder" -destination 'platform=iOS Simulator,name=iPhone 16' build
```

Then use the iOS Simulator control tool to: boot/attach to a simulator, launch the built app, tap the "Video" chip, grant the camera permission prompt, confirm the live preview appears above the mic button (the iOS Simulator provides a synthetic test-pattern camera feed), start a recording, stop it, and confirm the recording is saved without errors. Take a screenshot at the point the preview is visible and at the point a recording completes.

Also build for macOS and confirm no build errors (a full manual macOS run — granting the camera TCC prompt and confirming the FaceTime camera preview — should be done by a human with access to a real Mac display; note in your task completion report whether you were able to verify this manually or only confirmed the build):

```bash
xcodebuild -project "Maple Recorder.xcodeproj" -scheme "Maple Recorder" -destination 'platform=macOS' build
```

- [ ] **Step 6: Commit**

```bash
git add "Maple Recorder/Views/RecordingListView.swift"
git commit -m "feat: wire camera video recording into RecordingListView"
```

---

### Task 10: Video playback in `RecordingDetailView`

**Files:**
- Modify: `Maple Recorder/Views/RecordingDetailView.swift`

**Interfaces:**
- Consumes: `MapleRecording.videoFile: String?` (Task 1), `StorageLocation.recordingsURL` (existing).

- [ ] **Step 1: Add the AVKit import**

In `Maple Recorder/Views/RecordingDetailView.swift`, add after the existing platform imports (after line 6, before `struct RecordingDetailView`):

```swift
import SwiftUI
#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif
import AVKit
```

- [ ] **Step 2: Insert the video player section**

In `body`, insert `videoPlayerSection(recording: recording)` between `tagsSection` and `transcriptSection` (`Maple Recorder/Views/RecordingDetailView.swift:54-55`):

```swift
                        tagsSection(recording: recording)
                        #if !os(watchOS)
                        videoPlayerSection(recording: recording)
                        #endif
                        transcriptSection(recording: recording)
```

- [ ] **Step 3: Implement `videoPlayerSection`**

Add the new method near the other `*Section(recording:)` methods (e.g. right after `tagsSection`'s definition — find it with `grep -n "private func tagsSection" "Maple Recorder/Views/RecordingDetailView.swift"` and insert after its closing brace):

```swift
    #if !os(watchOS)
    @ViewBuilder
    private func videoPlayerSection(recording: MapleRecording) -> some View {
        if let videoFile = recording.videoFile {
            let videoURL = StorageLocation.recordingsURL.appendingPathComponent(videoFile)
            VideoPlayer(player: AVPlayer(url: videoURL))
                .frame(height: 220)
                .clipShape(.rect(cornerRadius: 12))
        }
    }
    #endif
```

- [ ] **Step 4: Build to verify it compiles**

Run: `xcodebuild -project "Maple Recorder.xcodeproj" -scheme "Maple Recorder" -destination 'platform=iOS Simulator,name=iPhone 16' build`
Run: `xcodebuild -project "Maple Recorder.xcodeproj" -scheme "Maple Recorder" -destination 'platform=macOS' build`
Expected: BUILD SUCCEEDED for both.

- [ ] **Step 5: Manual verification**

Using the recording produced in Task 9 Step 5 (a recording with a saved `.mov`), open its detail view in the running iOS Simulator app and confirm the video player appears above the transcript and plays back the recorded clip. Screenshot it.

- [ ] **Step 6: Commit**

```bash
git add "Maple Recorder/Views/RecordingDetailView.swift"
git commit -m "feat: play back recorded video in RecordingDetailView"
```

---

### Task 11: Full test suite + final cross-platform build

**Files:** None (verification only).

- [ ] **Step 1: Run the full unit test suite**

Run: `xcodebuild -project "Maple Recorder.xcodeproj" -scheme "Maple Recorder" -destination 'platform=iOS Simulator,name=iPhone 16' test`
Expected: All tests PASS, including every test added in Tasks 1–3.

- [ ] **Step 2: Build every affected target**

```bash
xcodebuild -project "Maple Recorder.xcodeproj" -scheme "Maple Recorder" -destination 'platform=iOS Simulator,name=iPhone 16' build
xcodebuild -project "Maple Recorder.xcodeproj" -scheme "Maple Recorder" -destination 'platform=macOS' build
xcodebuild -project "Maple Recorder.xcodeproj" -scheme "Maple Recorder Watch App" -destination 'platform=watchOS Simulator,name=Apple Watch Series 10 (46mm)' build
```
Expected: BUILD SUCCEEDED for all three — the watchOS target in particular confirms every new file was correctly excluded there.

- [ ] **Step 3: End-to-end manual pass on iOS Simulator**

Full flow: launch the app → toggle "Video" on → grant camera permission → see live preview → start recording (mic button) → confirm preview stays visible with the elapsed-time counter → stop recording → open the new recording → confirm the video plays back above the transcript and audio playback bar still works → go to Settings → Recording section → confirm the Camera picker lists at least "Default" (simulators typically expose no real device beyond the synthetic test camera, so the list may be short — that's expected). Report what was and wasn't verifiable in the simulator versus what needs a real device/Mac.

- [ ] **Step 4: Report status**

Summarize: tests passed/failed, which builds succeeded, what was manually verified vs. what still needs a human with real hardware (physical Mac camera, physical iPhone front camera) to confirm.
