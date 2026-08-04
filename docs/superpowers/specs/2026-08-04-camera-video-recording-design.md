# Camera Video Recording — Design Spec

**Date:** 2026-08-04
**Status:** Approved

## Problem

Users want to record themselves on camera while recording audio (e.g. a solo video journal or talk), and still get the existing transcript/summary pipeline. Today the app only captures audio (mic + optional macOS system audio). There is no camera code anywhere in the codebase.

## Goals

- Add an opt-in camera video recording path on **iOS and macOS** (not watchOS).
- A FAB control to toggle video recording on/off, visually consistent with the existing "Include system audio" control.
- A live camera preview visible while video recording is armed and while recording.
- The recorded video is saved alongside the audio/markdown pair and playable from the recording's detail view.
- A Settings page to choose which camera device to use.

## Non-Goals

- No video chunking/segmentation. Audio uses 30-minute VAD-based chunking for ASR; video doesn't feed the transcription pipeline, so it's written as a single continuous file per recording.
- No inline camera-picker menu on the FAB — device selection lives in Settings only.
- No watchOS support (no camera use case there).
- No use of the video track's pixels or audio for transcription/diarization — the existing audio-only pipeline is untouched.
- No support in `QuickRecordPanel` (the hotkey-driven quick-capture panel) — camera UI only appears in the main `RecordingListView` recording flow.

## Architecture

Video capture is a new, independent path that does not touch the audio/transcription pipeline. A new `Maple Recorder/Video/` group:

- **`VideoRecorder`** (`@Observable final class`) — owns an `AVCaptureSession` + `AVCaptureMovieFileOutput`. Captures **video only** (no audio input added to the session) so mic capture stays solely `AudioRecorder`'s responsibility and the two never compete for the microphone. Responsibilities: permission check/request (`AVCaptureDevice.requestAccess(for: .video)`), session configuration using the camera selected in Settings (`SettingsManager.preferredCameraID`, falling back to a sensible default), starting/stopping the capture session (drives the live preview), starting/stopping the movie file output (drives the saved `.mov`).
- **`CameraPreviewView`** — `UIViewRepresentable` (iOS) / `NSViewRepresentable` (macOS) wrapping an `AVCaptureVideoPreviewLayer` bound to `VideoRecorder`'s session.

**Why a separate class instead of folding into `AudioRecorder`:** `AudioRecorder` already juggles mic capture, macOS system audio, chunking, and silence detection — camera capture is an unrelated hardware pipeline (its own session, its own device, its own file). Keeping it separate matches single-responsibility and means `AudioRecorder` doesn't need to know video exists. `RecordingListView` owns both `recorder: AudioRecorder` and `videoRecorder: VideoRecorder` and coordinates start/stop together, the same place it already coordinates `recorder` with `miniRecordingController`.

## UI

### FAB controls (`RecordingListView`)

Both "Include system audio" and "Record video" become a shared pill/chip toggle component, **`RecordingOptionChip`** (icon + label, filled when active, outlined when inactive) in `Views/Components/`, replacing the current macOS-only native `.checkbox` toggle style. This fixes the mismatch of adding a second, differently-styled control next to the checkbox, and — since there's no native checkbox style on iOS — lets "Record video" work on both platforms with one implementation.

Layout in the FAB `VStack`, below the mic button, when not recording:
- macOS: `[🔊 Include system audio]  [🎥 Record video]`
- iOS: `[🎥 Record video]` only (system audio capture remains macOS-only ScreenCaptureKit; unrelated to this feature)

### Live preview

When "Record video" is on, a `CameraPreviewView` appears inline in the same `VStack`, above the mic button. It stays visible through both the idle/armed state and while actively recording, so the user can see themselves the whole time.

### Recording detail (`RecordingDetailView`)

A new `videoPlayerSection` (AVKit `VideoPlayer`) is inserted between `tagsSection` and `transcriptSection`, shown only when the recording has a saved video file.

### Settings (`SettingsView`)

A new "Camera" section, following the existing `SettingsCard` + `SettingsSectionHeader` + `Picker(...).pickerStyle(.menu)` pattern (mirrors the Provider picker). Lists devices via `AVCaptureDevice.DiscoverySession(deviceTypes:mediaType: .video, position: .unspecified)`. On iOS, front and back cameras are listed as separate entries.

## Data model & storage

Video is saved as `{uuid}.mov`, sibling to `{uuid}.md` / `{uuid}.m4a` in `StorageLocation.recordingsURL`. `AudioRecorder` remains the one place that mints the session's `recordingId` (as it does today); `RecordingListView.startRecording()` reads `recorder.recordingId` after starting audio and passes it into `videoRecorder.startRecording(id:)` so both capture paths write files under the same UUID.

Following the existing precedent for `audioFiles`/`systemAudioFiles` (explicit filename tracking rather than existence-sniffing), `MapleRecording` gets a new optional field:

```swift
var videoFile: String?   // filename only, relative to StorageLocation.recordingsURL; nil if no video was recorded
```

This flows through `MetadataJSON` as `video` (optional, `decodeIfPresent` for backward compatibility with existing recordings that predate this field — same pattern already used for `systemAudio`/`tags`), and through `RecordingStore`'s save/delete/rename logic so video files are cleaned up and moved together with their audio/markdown siblings.

## Settings persistence

`AppSettings` gets a new field `preferredCameraID: String?` (the `AVCaptureDevice.uniqueID`), exposed via a computed property on `SettingsManager`, following the same JSON-backed pattern as `preferredLLMProvider` (not `@AppStorage`). `nil` means "use the default camera."

**Default camera when unset:** front/selfie camera on iOS (matches the "recording of myself" use case), first built-in camera on macOS.

## Permissions

- Add `NSCameraUsageDescription` to `Info.plist` (currently only `NSMicrophoneUsageDescription` exists).
- The macOS target has `ENABLE_APP_SANDBOX = YES` but its `.entitlements` file currently has no `com.apple.security.device.camera` (or even `.microphone`) key — mic capture evidently works today via some Xcode-managed mechanism not visible in the checked-in entitlements file. Add `com.apple.security.device.camera` defensively; verify camera access actually works when building, and adjust if needed.
- If camera permission is denied, the "Record video" chip shows an inline error state (mirroring the existing error-banner pattern already in `RecordingListView`) rather than silently failing to preview/record.

## Error handling

- Permission denied/restricted → inline error banner near the chip, video recording stays off.
- Camera becomes unavailable mid-recording (e.g. unplugged external webcam) → stop video capture gracefully, keep audio recording running (video is supplementary; losing it shouldn't kill the whole recording). Surface a non-blocking warning, mirroring `AudioRecorder.recordingWarning`.

## Testing

- `SettingsManager`/`AppSettings` persistence of `preferredCameraID` — unit test mirroring existing settings tests.
- `MapleRecording.MetadataJSON` round-trip (encode/decode) including the new optional `video` field, and backward-compat decoding of old JSON without it.
- Camera capture itself isn't meaningfully unit-testable — verified manually via simulator/device build (iOS Simulator provides a synthetic camera; macOS build uses the built-in FaceTime camera or a connected/Continuity camera).
