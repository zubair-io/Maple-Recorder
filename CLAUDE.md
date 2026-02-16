# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Maple Recorder is a privacy-first, fully local voice recording and transcription app for Apple platforms (iOS, macOS, watchOS). It records audio, transcribes with speaker diarization using FluidAudio, generates on-device summaries via Apple Foundation Models, and stores everything as portable Markdown + audio file pairs.

**Current state:** Early-stage scaffold (Xcode template with placeholder SwiftData model). The comprehensive design spec lives in `Maple Recorder — maple-recorder-design-doc.md`.

## Build & Test

This is a native Xcode project (no SPM packages, CocoaPods, or Carthage yet).

```bash
# Build
xcodebuild -project "Maple Recorder.xcodeproj" -scheme "Maple Recorder" -destination 'platform=iOS Simulator,name=iPhone 16' build

# Run unit tests (Swift Testing framework)
xcodebuild -project "Maple Recorder.xcodeproj" -scheme "Maple Recorder" -destination 'platform=iOS Simulator,name=iPhone 16' test

# Run UI tests only
xcodebuild -project "Maple Recorder.xcodeproj" -scheme "Maple Recorder" -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:"Maple RecorderUITests" test
```

Deployment targets: iOS 26.1, macOS 26.1, xOS 26.1. Multi-platform via `SDKROOT: auto`.

## Architecture

The design document specifies a 4-layer architecture:

- **UI Layer (SwiftUI):** `RecordingList`, `RecordingDetailView`, `PlaybackBar`, `WaveformView`, `TranscriptListView`, `SpeakerEditor`, `PromptsView`. Uses `@Observable` for reactivity and `NavigationSplitView` for adaptive layout.
- **Audio Layer (AVFoundation):** `AudioRecorder` (AVAudioEngine), `AudioPlayer`, `SystemAudioCapture` (macOS ScreenCaptureKit), `AudioMixer`, `PlaybackSyncEngine` (CADisplayLink-driven word highlighting at 60fps).
- **ML Layer:** `TranscriptionManager` (FluidAudio Parakeet TDT v3 ASR), `DiarizationManager` (Pyannote offline), `TranscriptMerger`, `Summarizer` (Apple Foundation Models), `PromptRunner`.
- **Storage Layer:** `RecordingStore` (single source of truth), `MarkdownSerializer`, `FileSystemManager`. Files stored in iCloud Drive with local fallback.

### Data Flow

Recording → AVAudioEngine capture → Resample 48kHz→16kHz mono → ASR + diarization in parallel → TranscriptMerger aligns results → Summarizer generates summary → MarkdownSerializer persists to `.md` + `.m4a` → UI updates.

### File Format

Each recording is a Markdown file + audio pair in `iCloud Drive/Documents/recordings/`:
- `{uuid}.md` — Title as H1, summary paragraph, JSON metadata block (in fenced code block) containing transcript segments with word-level timestamps, speaker info with embeddings, and prompt results.
- `{uuid}.m4a` — AAC audio at 48kHz/128kbps. Chunked at 30-minute boundaries using VAD-based silence detection.

### Platform-Specific Code

Use `#if os(iOS)`, `#if os(macOS)`, `#if os(watchOS)` for platform-specific features. macOS adds system audio capture via ScreenCaptureKit. watchOS is recording-only, transferring to iPhone via WatchConnectivity for processing.

## Key Dependencies (Planned)

- **FluidAudio 0.12+** — ASR, diarization, VAD (Apache 2.0)
- **Apple Foundation Models** — On-device LLM for summaries and custom prompts (iOS 26+/macOS 26+)
- **ScreenCaptureKit** — macOS system audio capture
- **Anthropic/OpenAI Swift SDKs** — Optional cloud LLM providers (API keys stored in Keychain)

## Design Conventions

- **Color palette:** Maple brown (#993629) primary, warm neutrals, 8 distinct speaker colors. No pure black or white — use warm undertones throughout.
- **Typography:** SF Pro (body), SF Pro Rounded (titles), SF Mono (timestamps).
- **Bundle ID:** `com.just.maple.Maple-Recorder`
- **Security:** App Sandbox enabled, Hardened Runtime enabled. Audio never leaves the device by default. API keys in Keychain only.
