# Maple Recorder — Product & Technical Design Document

**Version:** 1.0  
**Author:** Zubair  
**Date:** February 15, 2026  
**Status:** Draft

---

## 1. Overview

Maple Recorder is a privacy-first, fully local voice recording and transcription app for Apple platforms (iOS, macOS, watchOS). It records audio, transcribes with speaker diarization and timestamps using FluidAudio, generates on-device summaries, and stores everything as portable Markdown + audio file pairs in the local filesystem. Users can define custom system prompts for post-transcription AI processing, all powered by on-device models.

### 1.1 Design Principles

- **Local-first, always.** No audio, transcripts, or personal data leave the device. All ML inference runs on-device via CoreML / Apple Neural Engine.
- **Portable output.** Each recording produces a human-readable Markdown file and an audio file — no proprietary database, no lock-in.
- **Minimal friction.** One tap to record, one tap to stop. Everything else happens automatically.
- **Platform-native.** SwiftUI across all platforms, respecting each platform's interaction model (touch, pointer, crown).

### 1.2 Target Platforms

| Platform | Min OS | Role |
|----------|--------|------|
| iOS | 26.0+ | Primary recording + full processing |
| macOS | 26.0+ | Primary recording (mic + system audio) + full processing |
| watchOS | 26.0+ | Lightweight recording + playback, transfers to iPhone for processing |

---

## 2. User Experience

### 2.1 App Launch — Recording List

The app opens to a list view showing all saved recordings. Each row displays the recording title (default: timestamp), duration, and a truncated summary preview. Recordings are sorted by date descending. Tapping a recording opens the detail view with full transcript, summary, and audio playback.

The recording files live in the app's default documents directory, making them accessible via Files.app on iOS and Finder on macOS.

### 2.2 Recording Flow

```
┌─────────────────────────────────────────────────┐
│                                                   │
│   ┌─────────────────────────────────────────┐     │
│   │         Recording List                   │     │
│   │  ┌──────────────────────────────┐        │     │
│   │  │ 📄 Team Standup 2/15         │        │     │
│   │  │    3:42 · "Discussed sprint  │        │     │
│   │  │    priorities and blockers…" │        │     │
│   │  ├──────────────────────────────┤        │     │
│   │  │ 📄 Design Review 2/14       │        │     │
│   │  │    12:08 · "Reviewed new…"  │        │     │
│   │  └──────────────────────────────┘        │     │
│   └─────────────────────────────────────────┘     │
│                                                   │
│              ┌──────────────┐                     │
│              │  ⏺ Record    │                     │
│              └──────────────┘                     │
└─────────────────────────────────────────────────┘
```

**Recording state transitions:**

1. **Idle** → User taps Record button.
2. **Recording** → Button morphs to Stop (with animation). A live waveform visualization animates above the button showing audio levels. Timer displays elapsed time.
3. **Processing** → User taps Stop. UI shows progress indicator. FluidAudio runs transcription + diarization. Apple Foundation Models generate the summary.
4. **Complete** → Recording appears in the list. User is navigated to the detail view.

### 2.3 Recording Detail View

Tapping a recording in the list opens the detail view. This is the primary reading and editing interface for a completed recording.

#### Layout

```
┌──────────────────────────────────────────────────────┐
│  ← Back                                    ⋯ (menu)  │
├──────────────────────────────────────────────────────┤
│                                                       │
│  ┌──────────────────────────────────────────────┐    │
│  │  Team Standup — February 15, 2026       ✏️   │    │  ← Editable H1 title
│  └──────────────────────────────────────────────┘    │
│                                                       │
│  ┌──────────────────────────────────────────────┐    │
│  │  We discussed sprint priorities for the       │    │  ← Editable summary
│  │  next two weeks. The main blocker is the      │    │    paragraph
│  │  API migration which is expected to…          │    │
│  └──────────────────────────────────────────────┘    │
│                                                       │
│  ── Transcript ──────────────────────────────────    │
│                                                       │
│  ┌────────────┬─────────────────────────────────┐    │
│  │  0:00      │  Alright, let's get started      │    │
│  │  Zubair ✏️ │  with the standup.               │    │
│  ├────────────┼─────────────────────────────────┤    │
│  │  0:05      │  So the API migration is going   │    │
│  │  Alex   ✏️ │  well. I think we'll have it     │    │
│  │            │  wrapped up by ███████.           │    │  ← Highlighted word
│  ├────────────┼─────────────────────────────────┤    │
│  │  0:12      │  Great. Any blockers we need     │    │
│  │  Zubair ✏️ │  to address?                     │    │
│  └────────────┴─────────────────────────────────┘    │
│                                                       │
│  ── Custom Prompt Results ───────────────────────    │
│                                                       │
│  ┌──────────────────────────────────────────────┐    │
│  │  Action Items (via "Extract Action Items")    │    │
│  │                                               │    │
│  │  • Complete API migration by Thursday         │    │  ← Rendered markdown
│  │  • Alex to update documentation               │    │    from prompt result
│  │  • Schedule follow-up for Friday              │    │
│  └──────────────────────────────────────────────┘    │
│                                                       │
│  ┌──────────────────────────────────────────────┐    │
│  │  + Run Custom Prompt…                         │    │  ← Opens prompt picker
│  └──────────────────────────────────────────────┘    │
│                                                       │
├──────────────────────────────────────────────────────┤
│  ◀◀    ▶ / ⏸    ▶▶         0:05 / 3:42    1.0x     │  ← Playback bar
└──────────────────────────────────────────────────────┘
```

#### Editable Sections

**Title (H1)** — Tapping the title enters inline edit mode. Changes are saved to the Markdown file on commit (keyboard dismiss / tap outside). Default title is a formatted timestamp like "Recording — February 15, 2026 10:30 AM".

**Summary** — Tapping the summary paragraph enters a multi-line text editor. The summary is auto-generated on recording completion but the user can freely edit it afterward. Changes persist to the Markdown file.

**Speaker Names** — Each transcript segment shows the speaker label on the left. Tapping a speaker name opens an inline editor. Renaming a speaker updates all segments attributed to that speaker throughout the transcript and persists to the JSON block. The `speakers` array in the JSON metadata is also updated.

**Custom Prompt Results** — Rendered as read-only Markdown below the transcript. Each result shows which prompt generated it. Users can delete individual prompt results or run additional prompts.

#### Transcript Rendering

The transcript is displayed as a scrollable list of segments. Each segment row has two columns:

| Left Column (fixed width) | Right Column (flexible) |
|---------------------------|------------------------|
| Timestamp formatted as `M:SS` or `H:MM:SS` | Transcript text for the segment |
| Speaker name (tappable to edit) | Words highlighted during playback |

Segments from the same speaker are visually grouped. A speaker change introduces a subtle divider. Each speaker is assigned a consistent color throughout the transcript for quick visual scanning.

#### Playback & Word-Level Highlighting

A persistent playback bar sits at the bottom of the screen (above the safe area). Controls include play/pause, skip forward/back (15 seconds), elapsed/total time, and playback speed (0.5x, 1.0x, 1.5x, 2.0x).

**Word-level highlighting during playback:**

As audio plays, the currently spoken word(s) are highlighted in the transcript. This requires word-level timestamps in the data model. FluidAudio's Parakeet ASR produces segment-level timestamps, so word timing is derived by one of two approaches:

1. **Proportional estimation** — Distribute time evenly across words within a segment based on character count. Simple, imprecise, but works without additional ML.
2. **Forced alignment** — Run a second pass with a forced alignment model (e.g., CTC-based alignment from the ASR encoder output) to get precise per-word timestamps. More accurate but adds processing time.

The recommended approach is to start with proportional estimation (M1) and upgrade to forced alignment in a later milestone if precision is insufficient.

**Scroll behavior:** During playback, the transcript auto-scrolls to keep the currently active segment visible. A "scroll to now" button appears if the user manually scrolls away from the active segment, similar to how Voice Memos handles this. Auto-scroll pauses when the user is actively scrolling and resumes after 3 seconds of inactivity.

**Tap-to-seek:** Tapping any word in the transcript seeks the audio player to that word's timestamp. This works bidirectionally — tapping a future word seeks forward, tapping a past word seeks backward.

#### Overflow Menu (⋯)

The overflow menu provides secondary actions: rename recording, share (exports .md + .m4a), delete recording, and duplicate.

### 2.4 macOS-Specific: System Audio Capture

On macOS, a checkbox labeled "Include system audio" (off by default) appears next to the record button. When enabled, the app captures both microphone input and system audio output (speaker/headphone playback), enabling transcription of meetings, calls, or media playing on the device.

Implementation uses `ScreenCaptureKit` (macOS 13+) for system audio capture, mixed with `AVAudioEngine` microphone input into a single audio stream.

### 2.4 watchOS Flow

The watch app provides recording and playback only — no transcription or ML processing happens on-watch.

**Recording:** A single Record/Stop button with elapsed time and a simple audio level indicator. Recordings are captured locally on the watch and transferred to the paired iPhone via `WatchConnectivity` for transcription and processing. The watch displays a "Transferring…" state after recording completes and a confirmation once the iPhone has processed it.

**Playback:** Once a recording has been processed on the iPhone, the transcript and a compressed audio file sync back to the watch via iCloud Drive. The watch can display the transcript (speaker labels + text, no word-level highlighting) and play back the audio. This is useful for reviewing a recording on the go — e.g., listening back to a meeting while walking.

### 2.5 Post-Processing: Custom Prompts

After transcription completes, the user can optionally apply a **Custom Prompt** to the transcript. This enables workflows like:

- "Extract action items from this meeting"
- "Rewrite this as meeting notes in bullet format"
- "Identify key decisions and who made them"
- "Summarize for a Slack update"

Users manage custom prompts in Settings. Each prompt has a name and a system prompt body. When applying a prompt, the user can also add freeform additional context before execution.

The result is appended to the Markdown file as an additional section.

#### LLM Provider Options

Prompt execution and summary generation support multiple backends. The user selects their preferred provider in Settings:

| Provider | Requirements | Trade-offs |
|----------|-------------|------------|
| **Apple Foundation Models** | iOS 26+ / macOS 26+ (baseline), no API key needed | Fully local, free, available on all supported devices |
| **Claude API (Anthropic)** | API key, network access | Higher quality for complex prompts, usage-based cost |
| **OpenAI API** | API key, network access | High quality, broad model selection, usage-based cost |
| **None / Off** | — | Transcription only, no summary or prompt features |

The default is Apple Foundation Models — since the app targets iOS/macOS 26+, this is available on every supported device. Users who want higher-quality processing for complex prompts can add a Claude or OpenAI API key.

API keys are stored in the Keychain, never in the Markdown files or in iCloud. When a cloud provider is selected, only the transcript text is sent — never the raw audio. The app clearly communicates when data will leave the device (a badge or indicator on the prompt button showing "Cloud" vs "On-Device").

### 2.6 Siri & Shortcuts Integration

Maple Recorder exposes App Intents for the Shortcuts app and Siri:

| Intent | Description | Example Trigger |
|--------|-------------|-----------------|
| **Start Recording** | Begins a new recording | "Hey Siri, start a Maple recording" |
| **Stop Recording** | Stops the current recording and triggers processing | "Hey Siri, stop recording" |
| **List Recordings** | Returns recent recordings | Shortcut automation |
| **Get Transcript** | Returns the transcript text for a recording | Shortcut: pipe transcript into another app |
| **Run Prompt** | Applies a named custom prompt to a recording | Shortcut: "Extract action items from last recording" |

Implemented via the `AppIntents` framework (iOS 16+ / macOS 13+). Each intent conforms to `AppIntent` and returns structured results that can be chained in Shortcuts workflows. The "Start Recording" intent launches the app into recording mode with a `NSUserActivity` handoff.

---

## 3. Data Model & File Format

### 3.1 Storage Location

Recordings are stored in the app's **iCloud Drive container** when available, falling back to local Documents/ when iCloud is unavailable. This gives automatic cross-device sync for users signed into the same Apple ID.

```swift
struct StorageLocation {
    static var recordingsURL: URL {
        if let iCloud = FileManager.default
            .url(forUbiquityContainerIdentifier: nil)?
            .appendingPathComponent("Documents/recordings") {
            return iCloud  // Syncs across devices
        }
        return FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("recordings")  // Local fallback
    }
}
```

Files are visible in Files.app under "iCloud Drive > Maple Recorder" (iOS) and in Finder's iCloud Drive (macOS).

#### iCloud Sync Behavior

- **Markdown files** (< 50 KB typically) sync near-instantly across devices.
- **Audio files** (variable, ~1 MB/min at 128 kbps) sync in the background. On other devices, audio may initially be a **placeholder** (not yet downloaded). The UI shows the transcript immediately and displays a download indicator on the play button until the audio is available.
- **Conflict resolution** follows last-writer-wins using the `modified_at` timestamp in the JSON metadata block. Recordings are create-once, so true conflicts are rare — they only occur if the user edits a title or speaker name on two devices simultaneously.
- **Storage quota** — audio files count against the user's iCloud storage. The app surfaces total recording storage used in Settings so users can manage their space.

#### Directory Structure

Each recording is a **flat pair of files** in the recordings directory, named by UUID. No subdirectories per recording — this simplifies iCloud sync (fewer directory creation race conditions) and makes Files.app browsing cleaner.

```
iCloud Drive Container / Documents /
└── recordings/
    ├── a1b2c3d4-e5f6-7890-abcd-ef1234567890.md
    ├── a1b2c3d4-e5f6-7890-abcd-ef1234567890.m4a
    ├── f5e6d7c8-b9a0-1234-5678-abcdef123456.md
    ├── f5e6d7c8-b9a0-1234-5678-abcdef123456.m4a
    └── ...

App Support Directory (local, not synced)
├── models/
│   ├── parakeet-tdt-v3/
│   ├── speaker-diarization/
│   └── silero-vad/
├── config/
│   └── custom-prompts.json
└── cache/
    └── audio-download-state/
```

The `.md` and `.m4a` share the same UUID stem. The app discovers recordings by scanning for `.md` files and resolving the paired audio file by replacing the extension.

### 3.2 Markdown File Format

The `.md` file is the source of truth for all metadata and transcript data. It is human-readable, portable, and parseable.

```markdown
# Team Standup — February 15, 2026

We discussed sprint priorities for the next two weeks. The main blocker
is the API migration which is expected to complete by Thursday. Action
items were assigned to three team members covering testing, documentation,
and client communication.

~~~json
{
  "id": "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
  "audio": [
    "a1b2c3d4-e5f6-7890-abcd-ef1234567890.m4a"
  ],
  "duration": 222.5,
  "created_at": "2026-02-15T10:30:00Z",
  "modified_at": "2026-02-15T10:35:12Z",
  "speakers": [
    { "id": "speaker_0", "display_name": "Zubair", "color": "#4A90D9", "embedding": [0.123, -0.456, 0.789, "...256 floats"] },
    { "id": "speaker_1", "display_name": "Alex", "color": "#D94A4A", "embedding": [0.321, -0.654, 0.987, "...256 floats"] },
    { "id": "speaker_2", "display_name": "Speaker 3", "color": "#4AD97A", "embedding": [0.111, -0.222, 0.333, "...256 floats"] }
  ],
  "transcript": [
    {
      "speaker_id": "speaker_0",
      "start": 0.0,
      "end": 4.8,
      "text": "Alright, let's get started with the standup.",
      "words": [
        { "word": "Alright,", "start": 0.0, "end": 0.6 },
        { "word": "let's", "start": 0.6, "end": 0.9 },
        { "word": "get", "start": 0.9, "end": 1.1 },
        { "word": "started", "start": 1.1, "end": 1.6 },
        { "word": "with", "start": 1.6, "end": 1.9 },
        { "word": "the", "start": 1.9, "end": 2.1 },
        { "word": "standup.", "start": 2.1, "end": 4.8 }
      ]
    },
    {
      "speaker_id": "speaker_1",
      "start": 5.1,
      "end": 12.3,
      "text": "So the API migration is going well. I think we'll have it wrapped up by Thursday.",
      "words": [
        { "word": "So", "start": 5.1, "end": 5.3 },
        { "word": "the", "start": 5.3, "end": 5.5 },
        { "word": "API", "start": 5.5, "end": 5.9 },
        { "word": "migration", "start": 5.9, "end": 6.5 }
      ]
    }
  ],
  "prompt_results": [
    {
      "id": "f1e2d3c4-b5a6-7890-abcd-ef1234567890",
      "prompt_name": "Extract Action Items",
      "llm_provider": "apple_foundation_models",
      "result": "- Complete API migration by Thursday\n- Alex to update documentation\n- Schedule follow-up for Friday",
      "created_at": "2026-02-15T10:35:00Z"
    }
  ]
}
~~~

## Action Items

*Generated by "Extract Action Items" prompt — Apple Foundation Models*

- Complete API migration by Thursday
- Alex to update documentation
- Schedule follow-up for Friday
```

**Structure breakdown:**

| Section | Content |
|---------|---------|
| H1 heading | Title. Default is a formatted timestamp. User-editable in detail view. |
| First paragraph | Auto-generated summary via on-device ML or cloud LLM. User-editable in detail view. |
| Fenced code block (json) | Structured metadata: `audio` array (supports multi-part chunked recordings), speakers, transcript with word-level timestamps, prompt results with `llm_provider` attribution, and `modified_at` for iCloud conflict resolution. |
| H2 sections (optional) | Rendered output from custom prompt processing. Each section includes the prompt name, provider attribution, and Markdown-formatted result. |

Note: The `audio` field is an **array** to support long recordings that are chunked into multiple files (see Section 3.4).

### 3.3 Audio File Format

| Property | Value |
|----------|-------|
| Format | AAC in M4A container (`.m4a`) |
| Sample rate | 48 kHz (recording), resampled to 16 kHz for ML inference |
| Channels | Mono (mic), Stereo mixed to mono (macOS system audio + mic) |
| Bit rate | 128 kbps |
| Max file size | ~30 minutes per chunk (~28 MB at 128 kbps) |

AAC/M4A is chosen for the balance of quality, file size, and native Apple platform support. The audio file name matches the recording UUID from the JSON metadata block.

### 3.4 Long Recordings & Audio Chunking

Recordings longer than 30 minutes are automatically split into sequential audio chunks. This is transparent to the user — the UI presents a single continuous recording with seamless playback across chunks.

**Why chunk:**
- iCloud Drive handles many smaller files more reliably than single large files. A 2-hour meeting at 128 kbps is ~115 MB in a single file; as four 30-minute chunks, each is ~28 MB and can upload/download independently.
- On storage-constrained devices, iCloud can evict individual chunks. The app can stream playback from downloaded chunks while fetching the next one in the background.
- FluidAudio's offline diarizer already supports streaming from disk, so processing chunked audio adds no complexity to the ML pipeline.
- Device memory stays bounded during recording — each chunk is finalized and flushed to disk, so memory usage doesn't grow with recording length.

**Chunk naming convention:**

```
recordings/
├── a1b2c3d4-e5f6-7890-abcd-ef1234567890.md
├── a1b2c3d4-e5f6-7890-abcd-ef1234567890.m4a         ← Short recording (single file)
│
├── f5e6d7c8-b9a0-1234-5678-abcdef123456.md
├── f5e6d7c8-b9a0-1234-5678-abcdef123456_part1.m4a    ← Long recording
├── f5e6d7c8-b9a0-1234-5678-abcdef123456_part2.m4a    ← chunked into parts
├── f5e6d7c8-b9a0-1234-5678-abcdef123456_part3.m4a
└── f5e6d7c8-b9a0-1234-5678-abcdef123456_part4.m4a
```

The `audio` field in the JSON metadata lists all chunks in order:

```json
"audio": [
  "f5e6d7c8-b9a0-1234-5678-abcdef123456_part1.m4a",
  "f5e6d7c8-b9a0-1234-5678-abcdef123456_part2.m4a",
  "f5e6d7c8-b9a0-1234-5678-abcdef123456_part3.m4a",
  "f5e6d7c8-b9a0-1234-5678-abcdef123456_part4.m4a"
]
```

**Seamless playback:** The `AudioPlayer` loads chunks sequentially. When playback approaches the end of a chunk (within 5 seconds), it pre-loads the next chunk into a second `AVAudioPlayerNode` and crossfades at the boundary. Transcript timestamps are continuous across all chunks (they are not reset per chunk). Seeking jumps to the correct chunk by computing `targetChunkIndex = floor(seekTime / chunkDuration)`.

**Seamless recording:** During recording, the `AudioRecorder` monitors the current file duration. As the recording approaches the 30-minute mark, the recorder enters a "split-seeking" state where it monitors VAD output for a silence gap. If a silence of ≥ 300ms is detected within a ±30 second window around the target split point, the chunk boundary is placed at that silence. If no suitable silence is found within the window, a hard cut occurs at the 30:30 mark. The next chunk starts immediately with no audible gap. This ensures chunk boundaries never land mid-word while keeping chunks reasonably close to the target duration.

**Processing:** For transcription and diarization, all chunks are concatenated into a single 16 kHz sample buffer (or streamed via `StreamingAudioSampleSource` for very long recordings). The ML pipeline sees one continuous audio stream regardless of how it's stored on disk.

### 3.4 Data Model (Swift)

```swift
struct MapleRecording: Identifiable, Codable {
    let id: UUID
    var title: String
    var summary: String
    var audioFiles: [String]         // Array of audio filenames, supports chunked recordings
    var duration: TimeInterval
    var createdAt: Date
    var modifiedAt: Date             // Updated on any edit, used for iCloud conflict resolution
    var speakers: [Speaker]
    var transcript: [TranscriptSegment]
    var promptResults: [PromptResult]
}

struct Speaker: Identifiable, Codable {
    let id: String           // e.g. "speaker_0", "speaker_1" from diarization
    var displayName: String  // User-editable, defaults to "Speaker 1", "Speaker 2"
    var color: String        // Hex color assigned for UI consistency
    var embedding: [Float]?  // 256-d speaker embedding for cross-recording matching
}

struct TranscriptSegment: Identifiable, Codable {
    let id: UUID
    let speakerId: String    // References Speaker.id
    let start: TimeInterval
    let end: TimeInterval
    let text: String
    var words: [WordTiming]  // Word-level timestamps for playback highlighting
}

struct WordTiming: Identifiable, Codable {
    let id: UUID
    let word: String
    let start: TimeInterval
    let end: TimeInterval
}

enum LLMProvider: String, Codable, CaseIterable {
    case appleFoundationModels = "apple_foundation_models"
    case claude = "claude"
    case openai = "openai"
    case none = "none"
}

struct PromptResult: Identifiable, Codable {
    let id: UUID
    let promptName: String
    let promptBody: String       // The system prompt that was used
    let additionalContext: String?
    let llmProvider: LLMProvider // Which backend generated this result
    let result: String           // Markdown-formatted output
    let createdAt: Date
}

struct CustomPrompt: Identifiable, Codable {
    let id: UUID
    var name: String
    var systemPrompt: String
    var createdAt: Date
}

struct AppSettings: Codable {
    var preferredLLMProvider: LLMProvider  // User's default choice
    var claudeAPIKey: String?             // Stored in Keychain, reference only
    var openAIAPIKey: String?             // Stored in Keychain, reference only
    var iCloudEnabled: Bool               // Whether to use iCloud Drive
    var chunkDurationMinutes: Int = 30    // Audio chunk size for long recordings
}
```

---

## 4. Technical Architecture

### 4.1 High-Level Architecture

```
┌──────────────────────────────────────────────────────────────────┐
│                        Maple Recorder                            │
├──────────────┬──────────────┬──────────────┬─────────────────────┤
│   UI Layer   │  Audio Layer │   ML Layer   │   Storage Layer     │
│  (SwiftUI)   │ (AVFoundation│ (FluidAudio  │  (FileManager +     │
│              │  + ScreenCap)│  + Foundation │   App Documents)    │
│              │              │    Models)   │                     │
├──────────────┼──────────────┼──────────────┼─────────────────────┤
│ RecordingList│ AudioRecorder│ Transcription│ RecordingStore      │
│ RecordingView│ AudioPlayer  │   Manager    │ MarkdownSerializer  │
│  DetailView  │ SystemAudio  │ Diarization  │ FileSystemManager   │
│  Transcript  │   Capture    │   Manager    │                     │
│    ListView  │ AudioMixer   │ Transcript   │                     │
│  PlaybackBar │              │   Merger     │                     │
│ WaveformView │              │ Summarizer   │                     │
│ PromptsView  │              │ PromptRunner │                     │
│ SpeakerEditor│              │              │                     │
└──────────────┴──────────────┴──────────────┴─────────────────────┘
```

### 4.2 Module Breakdown

#### Audio Layer

**AudioRecorder** — Manages `AVAudioEngine` for microphone capture. Records to a temporary file during the session, then moves to the final location on completion. Exposes real-time audio level data for the waveform visualization.

**SystemAudioCapture** (macOS only) — Uses `ScreenCaptureKit` (`SCStream`) to capture system audio output. Requires the user to grant screen recording permission (audio-only, no video capture). Mixed with microphone audio via **AudioMixer**.

**AudioMixer** (macOS only) — Combines microphone and system audio streams into a single `AVAudioPCMBuffer` for recording and ML processing. Handles sample rate alignment and level normalization.

**AudioPlayer** — Playback of recorded audio with seek support. Exposes current playback time as an `@Published` property for SwiftUI binding. Drives the playback sync engine.

**PlaybackSyncEngine** — Bridges the audio player's current time with the transcript UI. On each display frame (via `CADisplayLink` on iOS / `CVDisplayLink` on macOS), it:

1. Reads the current playback time from `AudioPlayer`.
2. Binary-searches the transcript segments to find the active segment.
3. Binary-searches the active segment's `words` array to find the current word.
4. Publishes `activeSegmentId` and `activeWordId` to drive SwiftUI highlighting.
5. Determines whether auto-scroll should fire (if the active segment has changed and the user hasn't manually scrolled in the last 3 seconds).

```swift
@Observable
class PlaybackSyncEngine {
    var activeSegmentId: UUID?
    var activeWordId: UUID?
    var shouldAutoScroll: Bool = true

    private var lastManualScrollTime: Date = .distantPast
    private var displayLink: CADisplayLink?

    func tick(currentTime: TimeInterval, transcript: [TranscriptSegment]) {
        // Binary search for active segment
        guard let segment = transcript.first(where: {
            currentTime >= $0.start && currentTime < $0.end
        }) else { return }

        activeSegmentId = segment.id

        // Binary search for active word within segment
        if let word = segment.words.last(where: { currentTime >= $0.start }) {
            activeWordId = word.id
        }

        // Auto-scroll logic
        let timeSinceManualScroll = Date().timeIntervalSince(lastManualScrollTime)
        shouldAutoScroll = timeSinceManualScroll > 3.0
    }

    func userDidScroll() {
        lastManualScrollTime = Date()
        shouldAutoScroll = false
    }

    func seekToWord(_ word: WordTiming) {
        // Delegate to AudioPlayer to seek
    }
}
```

#### ML Layer

**TranscriptionManager** — Wraps FluidAudio's `AsrManager` with Parakeet TDT v3. Accepts 16 kHz mono Float32 samples, returns timestamped text segments. Handles model download on first use with progress reporting.

```swift
class TranscriptionManager {
    private var asrManager: AsrManager?

    func initialize() async throws {
        let models = try await AsrModels.downloadAndLoad(version: .v3)
        asrManager = AsrManager(config: .default)
        try await asrManager?.initialize(models: models)
    }

    func transcribe(_ samples: [Float]) async throws -> [TranscriptSegment] {
        let result = try await asrManager?.transcribe(samples)
        // Map FluidAudio results to TranscriptSegment model
    }
}
```

**DiarizationManager** — Wraps FluidAudio's `OfflineDiarizerManager`. Processes the same audio samples to produce speaker-labeled time ranges. Uses the offline pipeline (VBx clustering) for best accuracy.

```swift
class DiarizationManager {
    private var diarizer: OfflineDiarizerManager?

    func initialize() async throws {
        let config = OfflineDiarizerConfig()
        diarizer = OfflineDiarizerManager(config: config)
        try await diarizer?.prepareModels()
    }

    func diarize(_ samples: [Float]) async throws -> DiarizationResult {
        return try await diarizer!.process(audio: samples)
    }
}
```

**TranscriptMerger** — Aligns ASR output (text + timestamps) with diarization output (speaker + time ranges) into unified `TranscriptSegment` objects. The merge algorithm:

1. For each ASR segment, find the diarization segment with the greatest time overlap.
2. Assign the speaker label from the best-matching diarization segment.
3. Handle edge cases: segments that straddle speaker boundaries are assigned to the speaker with majority overlap.
4. Merge consecutive segments from the same speaker if the gap is < 1.0 second.

```swift
struct TranscriptMerger {
    static func merge(
        asrSegments: [AsrSegment],
        diarizationResult: DiarizationResult
    ) -> [TranscriptSegment] {
        // For each ASR segment, find best overlapping speaker
        // Coalesce adjacent same-speaker segments
    }
}
```

**Summarizer** — Generates a concise summary paragraph from the transcript text. Uses Apple's Foundation Models framework (NLModel or on-device generative model) on iOS 26+ / macOS 26+. On earlier OS versions, uses a simpler extractive summarization approach via NaturalLanguage framework.

**PromptRunner** — Executes custom user prompts against the transcript. Takes the system prompt, optional user-provided additional context, and the full transcript as input. Runs inference via Foundation Models on-device.

#### Storage Layer

**RecordingStore** — Manages CRUD operations on recordings by reading/writing Markdown files from the documents directory. Acts as the single source of truth. Provides a published array of recordings for SwiftUI observation.

**MarkdownSerializer** — Serializes `MapleRecording` to the defined Markdown format and parses it back. Handles the H1 title, summary paragraph, and JSON code block as discrete sections.

```swift
struct MarkdownSerializer {
    static func serialize(_ recording: MapleRecording) -> String {
        var md = "# \(recording.title)\n\n"
        md += "\(recording.summary)\n\n"
        md += "~~~json\n"
        md += jsonEncode(recording.metadata)
        md += "\n~~~\n"
        return md
    }

    static func deserialize(_ markdown: String) -> MapleRecording? {
        // Parse H1 for title
        // Parse first paragraph for summary
        // Extract JSON from fenced code block
    }
}
```

**FileSystemManager** — Handles directory creation, file moves, and cleanup. Ensures the `recordings/` directory structure exists. Manages the temporary recording file lifecycle.

### 4.3 Processing Pipeline

```
Record Stop
    │
    ▼
┌──────────────┐
│  Save Audio   │  Write .m4a to final location
│  to Disk      │
└──────┬───────┘
       │
       ▼
┌──────────────┐
│  Resample     │  48kHz → 16kHz mono Float32
│  Audio        │  via FluidAudio.AudioConverter
└──────┬───────┘
       │
       ├────────────────────┐
       │                    │
       ▼                    ▼
┌──────────────┐   ┌───────────────┐
│  ASR          │   │  Diarization   │
│  (Parakeet)   │   │  (Pyannote)    │
│  → text +     │   │  → speaker +   │
│    timestamps  │   │    time ranges │
└──────┬───────┘   └───────┬───────┘
       │                    │
       └────────┬───────────┘
                │
                ▼
       ┌───────────────┐
       │  Merge         │  Align ASR text with
       │  Transcript    │  speaker labels
       └───────┬───────┘
               │
               ▼
       ┌───────────────┐
       │  Summarize     │  On-device summary
       └───────┬───────┘
               │
               ▼
       ┌───────────────┐
       │  Write .md     │  Serialize to Markdown
       └───────────────┘
```

ASR and diarization run concurrently on the same audio buffer since they are independent operations. The merge step waits for both to complete.

### 4.4 watchOS Architecture

The watch app is intentionally minimal:

```
┌─────────────────────────────┐
│     watchOS App              │
│  ┌───────────────────────┐  │
│  │  AudioRecorder         │  │  AVAudioRecorder (not AVAudioEngine)
│  │  (compressed M4A)      │  │  Smaller file for transfer
│  └───────────┬───────────┘  │
│              │               │
│  ┌───────────▼───────────┐  │
│  │  WatchConnectivity     │  │  transferFile() to iPhone
│  │  Transfer Manager      │  │
│  └───────────────────────┘  │
└─────────────────────────────┘
         │
         │  WCSession file transfer
         ▼
┌─────────────────────────────┐
│     iOS App                  │
│  ┌───────────────────────┐  │
│  │  WatchTransferHandler  │  │  Receives file, triggers
│  │                        │  │  full processing pipeline
│  └───────────────────────┘  │
└─────────────────────────────┘
```

The watch uses `AVAudioRecorder` (simpler API, lower memory) rather than `AVAudioEngine`. Audio is compressed to M4A on-watch to minimize transfer size. The iPhone companion handles all ML processing.

### 4.5 Model Lifecycle

FluidAudio models must be downloaded from HuggingFace on first use. The app handles this gracefully:

1. **First launch** — Show an onboarding screen explaining that models need to be downloaded (~500MB total for ASR + diarization). Offer a "Download Models" button.
2. **Download progress** — Display progress for each model (ASR, segmentation, embedding, PLDA).
3. **Model validation** — On each launch, verify models exist and are valid via `AsrModels.isModelValid`. Re-download if corrupted.
4. **Recording before download** — If models aren't downloaded, still allow recording. Queue transcription for when models become available.

---

## 5. Platform-Specific Considerations

### 5.1 iOS

- Background audio recording via `AVAudioSession` category `.playAndRecord` with `.allowBluetooth` option.
- Background processing for transcription: use `BGProcessingTaskRequest` if the app moves to background during ML inference.
- Files.app integration via default documents directory.

### 5.2 macOS

- System audio capture requires Screen Recording permission (Privacy & Security → Screen Recording). The app should explain why this permission is needed and only request it when the user enables the "Include system audio" checkbox.
- `ScreenCaptureKit` (`SCStream`) configured for audio-only capture (no video frames).
- No sandboxing restrictions on the documents directory — recordings are directly accessible in Finder.
- Menu bar presence optional (future): quick-record from menu bar without opening the full app.

### 5.3 watchOS

- Memory constraints: watchOS has tight memory limits. No ML models loaded on watch.
- `WKExtendedRuntimeSession` for recording sessions longer than the default background limit.
- `WatchConnectivity` `transferFile()` for reliable background file transfer to iPhone.
- Watch shows transfer status and a confirmation once processing completes on the phone.

---

## 6. Theme & Visual Design

The Maple Recorder theme is derived from the Just Maple web design system, translated to native SwiftUI `Color` values. Both light and dark appearances use warm undertones — never pure black, never pure white — with the signature maple brown as the accent color.

### 6.1 Design Principles

1. **Never pure black.** Dark mode backgrounds use warm charcoal (`#1C1917`), not `#000000`.
2. **Never pure white backgrounds.** Light mode uses warm cream (`#FDFBF7`) as the base.
3. **Accent stays constant.** Maple brown `#993629` works across both themes without adaptation.
4. **Warm undertones throughout.** All neutrals pull from the stone color scale, giving the app a grounded, organic feel that matches the "Maple" identity.
5. **Elevation through surface, not shadow.** In dark mode, higher surfaces are lighter. In light mode, subtle shadows provide depth.
6. **Respect the platform.** Use standard SwiftUI materials (`.ultraThinMaterial`, `.regularMaterial`) for translucency where appropriate (playback bar, toolbars), tinted to the warm palette.

### 6.2 Color Palette

#### Core Colors

```
                              Light           Dark
                              ─────           ────
Accent / Primary              #993629         #993629      Maple brown
Accent Hover                  #7A2B21         #7A2B21      Darker maple
Accent Light                  #F5E6E4         #422016      Tinted highlight
```

#### Backgrounds

```
                              Light           Dark
                              ─────           ────
Background                    #FDFBF7         #1C1917      Page / root
Surface                       #FFFFFF         #262524      Cards, panels
Surface Alt                   #F5F2EB         #2E2C2A      Sidebar, grouped bg
Surface Hover                 #F5F5F4         #3A3836      Hover state
Input Background              #FFFFFF         #1C1917      Text fields
```

#### Text

```
                              Light           Dark
                              ─────           ────
Text Primary                  #292524         #E7E5E4      Headings, body
Text Secondary                #78716C         #A8A29E      Timestamps, labels
```

#### Borders & Dividers

```
                              Light           Dark
                              ─────           ────
Border                        #E7E5E4         #44403C      Dividers, outlines
```

#### Semantic

```
                              Light           Dark
                              ─────           ────
Error                         #DC3545         #DC3545      Destructive actions
Success                       #28A745         #28A745      Completion states
Info                          #007BFF         #007BFF      Informational
```

#### Speaker Colors

A fixed palette of 8 speaker colors, chosen to be distinguishable from each other and readable against both light and dark surfaces. Speaker colors are assigned in order and cycle if more than 8 speakers are detected.

```
Speaker 1     #4A90D9      Slate blue
Speaker 2     #D94A4A      Warm red
Speaker 3     #4AD97A      Green
Speaker 4     #D9A84A      Amber
Speaker 5     #9B59B6      Purple
Speaker 6     #1ABC9C      Teal
Speaker 7     #E67E22      Orange
Speaker 8     #7F8C8D      Cool gray
```

In the transcript view, speaker colors are used as a left-edge accent bar on each segment and as the speaker name label color. The transcript text itself always uses `Text Primary` for readability.

### 6.3 Typography

| Role | iOS / macOS | watchOS | Usage |
|------|-------------|---------|-------|
| Title (H1) | SF Pro Rounded, 28pt, semibold | SF Pro Rounded, 20pt, semibold | Recording title |
| Summary | SF Pro, 16pt, regular | — | Summary paragraph |
| Transcript text | SF Pro, 15pt, regular | — | Spoken words |
| Speaker label | SF Pro, 13pt, medium | SF Pro, 14pt, medium | Speaker name + timestamp |
| Timestamp | SF Pro Mono, 13pt, regular | SF Pro Mono, 12pt, regular | Time markers |
| Code / JSON | SF Mono, 13pt, regular | — | Debug / raw view |
| Button | SF Pro, 16pt, semibold | SF Pro, 16pt, semibold | Actions |

SF Pro is the system default and requires no bundling. SF Mono is used for timestamps to keep digits aligned. SF Pro Rounded is used for the recording title to give it a warmer, friendlier feel.

### 6.4 SwiftUI Implementation

The theme is implemented as a Swift asset catalog + a `MapleTheme` namespace for programmatic access.

#### Asset Catalog (Colors.xcassets)

Each color is defined as a named Color Set with "Any Appearance" and "Dark" variants. This gives automatic light/dark switching via `Color("mapleBackground")` and also works in Interface Builder / Storyboards if ever needed.

```
Colors.xcassets/
├── Maple/
│   ├── maplePrimary.colorset/        → #993629 / #993629
│   ├── maplePrimaryHover.colorset/   → #7A2B21 / #7A2B21
│   ├── maplePrimaryLight.colorset/   → #F5E6E4 / #422016
│   ├── mapleBackground.colorset/     → #FDFBF7 / #1C1917
│   ├── mapleSurface.colorset/        → #FFFFFF / #262524
│   ├── mapleSurfaceAlt.colorset/     → #F5F2EB / #2E2C2A
│   ├── mapleSurfaceHover.colorset/   → #F5F5F4 / #3A3836
│   ├── mapleTextPrimary.colorset/    → #292524 / #E7E5E4
│   ├── mapleTextSecondary.colorset/  → #78716C / #A8A29E
│   ├── mapleBorder.colorset/         → #E7E5E4 / #44403C
│   ├── mapleError.colorset/          → #DC3545 / #DC3545
│   ├── mapleSuccess.colorset/        → #28A745 / #28A745
│   └── mapleInfo.colorset/           → #007BFF / #007BFF
└── Speakers/
    ├── speaker0.colorset/            → #4A90D9
    ├── speaker1.colorset/            → #D94A4A
    ├── speaker2.colorset/            → #4AD97A
    ├── speaker3.colorset/            → #D9A84A
    ├── speaker4.colorset/            → #9B59B6
    ├── speaker5.colorset/            → #1ABC9C
    ├── speaker6.colorset/            → #E67E22
    └── speaker7.colorset/            → #7F8C8D
```

#### Theme Namespace

```swift
import SwiftUI

enum MapleTheme {

    // MARK: - Core

    static let primary          = Color("maplePrimary")
    static let primaryHover     = Color("maplePrimaryHover")
    static let primaryLight     = Color("maplePrimaryLight")

    // MARK: - Backgrounds

    static let background       = Color("mapleBackground")
    static let surface          = Color("mapleSurface")
    static let surfaceAlt       = Color("mapleSurfaceAlt")
    static let surfaceHover     = Color("mapleSurfaceHover")

    // MARK: - Text

    static let textPrimary      = Color("mapleTextPrimary")
    static let textSecondary    = Color("mapleTextSecondary")

    // MARK: - Border

    static let border           = Color("mapleBorder")

    // MARK: - Semantic

    static let error            = Color("mapleError")
    static let success          = Color("mapleSuccess")
    static let info             = Color("mapleInfo")

    // MARK: - Speakers

    static let speakerColors: [Color] = (0...7).map { Color("speaker\($0)") }

    static func speakerColor(for index: Int) -> Color {
        speakerColors[index % speakerColors.count]
    }
}
```

#### Usage in Views

```swift
// Recording list row
struct RecordingRow: View {
    let recording: MapleRecording

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(recording.title)
                .font(.headline)
                .foregroundStyle(MapleTheme.textPrimary)
            Text(recording.summary)
                .font(.subheadline)
                .foregroundStyle(MapleTheme.textSecondary)
                .lineLimit(2)
        }
        .padding()
        .background(MapleTheme.surface)
    }
}

// Transcript segment row
struct TranscriptRow: View {
    let segment: TranscriptSegment
    let speaker: Speaker
    let speakerIndex: Int
    let isActive: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Left column: timestamp + speaker
            VStack(alignment: .leading, spacing: 2) {
                Text(segment.start.formatted)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(MapleTheme.textSecondary)
                Text(speaker.displayName)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(MapleTheme.speakerColor(for: speakerIndex))
            }
            .frame(width: 80, alignment: .leading)

            // Right column: transcript text
            Text(segment.text)
                .font(.body)
                .foregroundStyle(MapleTheme.textPrimary)
        }
        .padding(.vertical, 8)
        .padding(.leading, 4)
        .overlay(alignment: .leading) {
            // Speaker color accent bar
            RoundedRectangle(cornerRadius: 2)
                .fill(MapleTheme.speakerColor(for: speakerIndex))
                .frame(width: 3)
        }
        .background(isActive ? MapleTheme.primaryLight : .clear)
    }
}

// Playback bar
struct PlaybackBar: View {
    @ObservedObject var player: AudioPlayer

    var body: some View {
        HStack(spacing: 16) {
            Button(action: player.skipBack) { Image(systemName: "gobackward.15") }
            Button(action: player.togglePlayPause) {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .font(.title2)
            }
            Button(action: player.skipForward) { Image(systemName: "goforward.15") }

            Spacer()

            Text("\(player.currentTime.formatted) / \(player.duration.formatted)")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(MapleTheme.textSecondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.regularMaterial)
        .overlay(alignment: .top) {
            Divider().overlay(MapleTheme.border)
        }
    }
}
```

### 6.5 Word Highlight Style

During playback, the currently active word is highlighted using a background capsule in `MapleTheme.primaryLight` with the text in `MapleTheme.primary`. This provides enough contrast without being distracting. The active segment row gets a subtle full-width background tint of `MapleTheme.primaryLight` at reduced opacity.

```swift
// Word-level text rendering with highlight
struct HighlightedTranscriptText: View {
    let words: [WordTiming]
    let activeWordId: UUID?
    let onTapWord: (WordTiming) -> Void

    var body: some View {
        // Build attributed text with tappable words
        words.reduce(Text("")) { result, word in
            let isActive = word.id == activeWordId
            return result + Text(word.word + " ")
                .foregroundColor(isActive ? MapleTheme.primary : MapleTheme.textPrimary)
                .background(isActive ? MapleTheme.primaryLight : .clear)
        }
        .font(.body)
    }
}
```

### 6.6 Waveform Visualization

The recording waveform uses `MapleTheme.primary` (`#993629`) for the active/current bars and `MapleTheme.primaryLight` for the trailing/faded bars. The waveform background is transparent, sitting over the recording screen's `MapleTheme.background`. Bar corner radius is 2pt, width 3pt, gap 2pt.

### 6.7 Platform Adaptations

**iOS** — Full theme as specified. The playback bar uses `.regularMaterial` for translucency, tinted warm by the underlying `MapleTheme.background`.

**macOS** — Same colors. Window chrome uses `.titleBar` style with the sidebar tinted `MapleTheme.surfaceAlt`. The playback bar can be a fixed-height bottom panel rather than a floating bar.

**watchOS** — Simplified palette. Background is system black (required by watchOS HIG). Accent color is `MapleTheme.primary` for the record button and active states. Text uses the system default white/gray. No custom surfaces — watchOS enforces its own hierarchy.

---

## 7. Dependencies

| Dependency | Version | Purpose | License |
|------------|---------|---------|---------|
| FluidAudio | 0.12+ | ASR (Parakeet), Speaker Diarization (Pyannote), VAD (Silero) | Apache 2.0 |
| Apple Foundation Models | iOS 26+ | On-device summarization and custom prompt execution | System |
| ScreenCaptureKit | macOS 14+ | System audio capture | System |
| WatchConnectivity | watchOS 10+ | Watch ↔ iPhone file transfer | System |
| AppIntents | iOS 16+ | Siri and Shortcuts integration | System |
| CloudKit / iCloud Drive | iOS 17+ | Cross-device file sync | System |

**Optional cloud LLM providers (user-configured):**

| Dependency | Purpose | Notes |
|------------|---------|-------|
| Anthropic Swift SDK | Claude API for summary + custom prompts | Network call, only transcript text sent — never audio |
| OpenAI Swift SDK | OpenAI API for summary + custom prompts | Network call, only transcript text sent — never audio |

The cloud SDKs are lightweight HTTP clients. They are included in the build but only activated when the user provides an API key and selects the provider. No network calls are made by default.

---

## 8. File System & Data Flow

```
iCloud Drive Container / Documents /          ← Syncs across devices
├── recordings/
│   ├── a1b2c3d4-e5f6-7890-abcd-ef1234567890.md
│   ├── a1b2c3d4-e5f6-7890-abcd-ef1234567890.m4a
│   ├── f5e6d7c8-b9a0-1234-5678-abcdef123456.md
│   ├── f5e6d7c8-b9a0-1234-5678-abcdef123456_part1.m4a
│   ├── f5e6d7c8-b9a0-1234-5678-abcdef123456_part2.m4a
│   ├── f5e6d7c8-b9a0-1234-5678-abcdef123456_part3.m4a
│   └── ...
└── prompts.json                              ← Custom prompt templates, syncs across devices

Local App Support Directory                   ← Never syncs
├── models/
│   ├── parakeet-tdt-v3/                      ← FluidAudio ASR models
│   ├── speaker-diarization/                  ← Pyannote CoreML models
│   └── silero-vad/                           ← VAD model
└── cache/
    └── audio-download-state/                 ← Tracks iCloud download progress
```

When iCloud is unavailable, the recordings directory falls back to the local app Documents/ directory with an identical structure.

---

## 9. Privacy & Security

- **Audio never leaves Apple infrastructure.** Recordings sync via iCloud Drive (Apple's encrypted infrastructure) and are never sent to third-party services. When using Claude or OpenAI for prompts, only the transcript text is sent — never raw audio.
- **iCloud encryption.** Files in iCloud Drive are encrypted in transit (TLS) and at rest. On devices with Advanced Data Protection enabled, files are end-to-end encrypted.
- **API keys in Keychain.** Claude and OpenAI API keys are stored in the iOS/macOS Keychain, never in Markdown files, never in iCloud, never in plain text.
- **Clear cloud indicators.** When a cloud LLM provider is active, the UI shows a visible "Cloud" badge on prompt-related actions so the user always knows when data will leave the device.
- **No analytics or telemetry.** Zero data collection by Maple Recorder.
- **Microphone permission** requested with clear explanation on first recording attempt.
- **Screen Recording permission** (macOS) requested only when system audio capture is enabled, with explanation.
- **iCloud opt-out.** Users can disable iCloud sync in Settings, keeping all recordings purely local.

---

## 10. Decisions Log

| Decision | Resolution | Notes |
|----------|-----------|-------|
| **iCloud Sync** | Yes — iCloud Drive document-based sync | `.md` files sync instantly, audio chunks sync in background. Last-writer-wins via `modified_at`. Falls back to local storage when iCloud unavailable. |
| **Real-time transcription** | Not needed | Transcription runs after recording stops. Batch processing is more accurate and simpler. |
| **Speaker naming** | Nice to have (M7) | Speaker names are editable in the detail view. Cross-recording speaker recognition via embeddings deferred to a polish milestone. |
| **Export formats** | Not needed | Markdown + audio is the format. Users can share via standard share sheet. |
| **Siri / Shortcuts** | Yes — App Intents | Start/stop recording, list recordings, get transcript, run prompt. |
| **LLM Providers** | Apple Foundation Models + Claude API + OpenAI API | Local-first default. Cloud providers optional via user-supplied API keys. Only transcript text sent, never audio. |
| **Watch standalone** | Recording + playback only | No ML processing on watch. Records locally, transfers to iPhone. Can play back and view transcript of processed recordings. |
| **Audio file naming** | UUID-based flat naming | `<uuid>.m4a` for short recordings, `<uuid>_partN.m4a` for chunked. No subdirectories per recording. |
| **Max recording length** | 30-minute chunk files, no hard limit | Audio auto-chunks at 30-min boundaries (preferring silence points). Transparent to user — single continuous recording in UI. Storage is the only real limit. |
| **Custom prompt sync** | Yes — `prompts.json` in iCloud container | Custom prompt templates sync across devices via a single `prompts.json` file in the iCloud Drive container alongside the recordings directory. Simple last-writer-wins merge. |
| **Speaker embedding persistence** | Yes — stored per recording | Speaker embeddings (~1 KB per speaker) are saved in the JSON metadata block. Enables future cross-recording speaker matching without re-processing audio. |
| **Chunk boundary precision** | VAD-based silence seeking | Chunk splits prefer the nearest silence point detected by VAD, but only if one occurs within a reasonable window (±30 seconds) of the target split time. If no silence is found within that window, hard-cut at the target time. This avoids mid-word cuts without holding a chunk open indefinitely. |
| **iCloud storage warnings** | Subtle, non-blocking indicator | Total recording storage usage is displayed in Settings as a simple label (e.g., "1.2 GB in iCloud"). No proactive alerts or pop-ups — the user checks when they want to. |
| **Claude/OpenAI model selection** | Sensible defaults, no user selection | Claude uses `claude-sonnet-4-5-20250929`, OpenAI uses `gpt-4o`. No model picker in the UI — keeps Settings simple. Can revisit if users request it. |
| **Offline prompt queue** | No queue — notify user to go online | If a cloud LLM provider is selected and the device is offline, the prompt button shows a disabled state with a message: "Connect to the internet to use [Claude/OpenAI]". No background queue. User can switch to Apple Foundation Models (on-device) for offline use, or retry when back online. |

---

## 12. Milestones

| Phase | Scope | Target |
|-------|-------|--------|
| **M0 — Foundation** | Audio recording + playback on iOS. iCloud Drive file storage with Markdown format. UUID-based flat file naming. Recording list UI. Maple theme (light + dark). | — |
| **M1 — Transcription** | FluidAudio integration. ASR + diarization + merge pipeline. Word-level timestamps (proportional estimation). Waveform visualization. Playback with word highlighting + tap-to-seek. | — |
| **M2 — Intelligence** | LLM provider abstraction (Apple Foundation Models + Claude + OpenAI). On-device summarization. Custom prompts UI and execution. API key management in Keychain. Cloud/local indicator badges. | — |
| **M3 — Long Recordings** | 30-minute audio chunking. Seamless recording across chunk boundaries. Seamless playback with pre-loading. iCloud-optimized chunk sync. | — |
| **M4 — macOS** | macOS app with system audio capture (ScreenCaptureKit). Shared codebase via SwiftUI multiplatform. Sidebar navigation. | — |
| **M5 — watchOS** | Watch recording app. WatchConnectivity transfer to iPhone. Playback + transcript viewing on watch. | — |
| **M6 — Siri & Shortcuts** | App Intents for start/stop recording, list recordings, get transcript, run prompt. Siri voice triggers. | — |
| **M7 — Polish** | Speaker naming across recordings (embedding persistence). Editable detail view refinements. Storage usage display. iCloud download states. | — |