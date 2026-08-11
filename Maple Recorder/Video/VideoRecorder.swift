#if !os(watchOS)
import AVFoundation
import Foundation
import Observation

/// TEMPORARY diagnostic aid for tracking down why video recordings sometimes
/// produce no .mov file on a real device — appends to a log file inside the
/// iCloud-synced recordings folder (readable from any Mac signed into the
/// same iCloud account) since live device console streaming isn't reliably
/// reachable for this app's Wi-Fi CoreDevice connection. Remove once the bug
/// is confirmed fixed.
func videoDebugLog(_ message: String) {
    print(message)
    let logURL = StorageLocation.recordingsURL.deletingLastPathComponent().appendingPathComponent("video-debug.log")
    let timestamp = ISO8601DateFormatter().string(from: Date())
    let line = "\(timestamp) \(message)\n"
    guard let data = line.data(using: .utf8) else { return }
    if FileManager.default.fileExists(atPath: logURL.path(percentEncoded: false)) {
        if let handle = try? FileHandle(forWritingTo: logURL) {
            handle.seekToEndOfFile()
            handle.write(data)
            try? handle.close()
        }
    } else {
        try? FileManager.default.createDirectory(at: logURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: logURL)
    }
}

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

    /// Set when the movie output finishes while no stopRecording() call is
    /// awaiting the result — e.g. the session was torn down mid-recording or
    /// the system ended the capture (phone call, camera pressure). The next
    /// stopRecording() returns this instead of losing the finished file.
    private var pendingFinishedURL: URL?

    /// Wall-clock time the movie file actually began writing (didStartRecording
    /// delegate) — i.e. where the video's timeline begins. Compared against
    /// AudioRecorder.micFirstBufferAt when muxing the mic audio into the video
    /// so the two tracks line up.
    private(set) var movieStartedAt: Date?

    override init() {
        super.init()
        session.sessionPreset = .high
        if session.canAddOutput(movieOutput) {
            session.addOutput(movieOutput)
        }
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleRuntimeError(_:)),
            name: AVCaptureSession.runtimeErrorNotification,
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

    /// Waits for the session to actually finish (re)configuring and starting
    /// before returning. Callers that gate video capture on `isVideoEnabled`
    /// (set the instant the user taps the chip, before the camera has powered
    /// on) instead of on this having completed can end up calling
    /// startRecording(id:) against a session with no connected input yet —
    /// AVCaptureMovieFileOutput silently records nothing in that case.
    func startSession(preferredDeviceID: String?) async {
        guard let device = Self.resolveDevice(preferredID: preferredDeviceID) else {
            captureError = "No camera available."
            return
        }
        videoDebugLog("[VideoRecorder] startSession: resolved device \(device.localizedName) (\(device.uniqueID))")
        await withCheckedContinuation { continuation in
            sessionQueue.async { [weak self] in
                guard let self else {
                    continuation.resume()
                    return
                }
                do {
                    let input = try AVCaptureDeviceInput(device: device)
                    self.session.beginConfiguration()
                    if let existing = self.deviceInput {
                        self.session.removeInput(existing)
                    }
                    let canAdd = self.session.canAddInput(input)
                    videoDebugLog("[VideoRecorder] startSession: canAddInput=\(canAdd)")
                    if canAdd {
                        self.session.addInput(input)
                        self.deviceInput = input
                    }
                    self.session.commitConfiguration()
                    self.session.startRunning()
                    let isRunning = self.session.isRunning
                    let connections = self.movieOutput.connections.count
                    videoDebugLog("[VideoRecorder] startSession: session.isRunning=\(isRunning), movieOutput connections=\(connections)")
                    Task { @MainActor in
                        self.isSessionRunning = isRunning
                        self.captureError = isRunning ? nil : "Camera failed to start."
                    }
                } catch {
                    let description = error.localizedDescription
                    videoDebugLog("[VideoRecorder] startSession: failed with error \(description)")
                    Task { @MainActor in
                        self.captureError = description
                    }
                }
                continuation.resume()
            }
        }
    }

    func stopSession() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.session.stopRunning()
            Task { @MainActor in
                self.isSessionRunning = false
            }
        }
    }

    func startRecording(id: UUID) {
        pendingFinishedURL = nil
        movieStartedAt = nil
        let tempDir = FileManager.default.temporaryDirectory
        let url = tempDir.appendingPathComponent("\(id.uuidString).mov")
        if FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) {
            try? FileManager.default.removeItem(at: url)
        }
        // Must run on sessionQueue, the same queue startSession/stopSession use to
        // drive the session — calling this directly on whatever thread the caller
        // is on let it race with a concurrent session.stopRunning(), which is how
        // this used to deadlock AVFoundation's internal session lock (app would
        // beachball right after stopping a video recording).
        sessionQueue.async { [weak self] in
            guard let self else { return }
            videoDebugLog("[VideoRecorder] startRecording: session.isRunning=\(self.session.isRunning), movieOutput.isRecording=\(self.movieOutput.isRecording), connections=\(self.movieOutput.connections.count), url=\(url.path)")
            self.movieOutput.startRecording(to: url, recordingDelegate: self)
        }
    }

    /// Stops the movie file recording and waits for it to finish writing. Callers
    /// must not stop the capture session until this returns — tearing the session
    /// down while the movie output is still finalizing is what caused the deadlock
    /// described above.
    func stopRecording() async -> URL? {
        // The recording may have already finished on its own (session torn
        // down mid-recording, system interruption) — hand over the held file.
        if let pending = pendingFinishedURL {
            pendingFinishedURL = nil
            videoDebugLog("[VideoRecorder] stopRecording: returning previously finished file")
            return pending
        }
        let url: URL? = await withCheckedContinuation { continuation in
            sessionQueue.async { [weak self] in
                guard let self, self.movieOutput.isRecording else {
                    videoDebugLog("[VideoRecorder] stopRecording: movieOutput.isRecording was false, nothing to stop")
                    continuation.resume(returning: nil)
                    return
                }
                videoDebugLog("[VideoRecorder] stopRecording: stopping active recording")
                self.recordingCompletion = continuation
                self.movieOutput.stopRecording()
            }
        }
        // The delegate can race the isRecording check above: if the recording
        // finished between this call starting and the sessionQueue block
        // running, its result landed in pendingFinishedURL instead.
        if url == nil, let pending = pendingFinishedURL {
            pendingFinishedURL = nil
            videoDebugLog("[VideoRecorder] stopRecording: recovered file that finished during stop")
            return pending
        }
        return url
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
    // AVFoundation invokes delegate methods from an arbitrary internal queue, not
    // necessarily the main actor — `nonisolated` lets it call in from there; the
    // body hops back to the main actor itself before touching any state.
    nonisolated func fileOutput(
        _ output: AVCaptureFileOutput,
        didStartRecordingTo fileURL: URL,
        from connections: [AVCaptureConnection]
    ) {
        // Capture the timestamp here, not after the actor hop — the hop's
        // queueing delay would skew the audio/video alignment it exists for.
        let startedAt = Date()
        videoDebugLog("[VideoRecorder] fileOutput didStartRecordingTo: \(fileURL.lastPathComponent)")
        Task { @MainActor in
            self.movieStartedAt = startedAt
        }
    }

    nonisolated func fileOutput(
        _ output: AVCaptureFileOutput,
        didFinishRecordingTo outputFileURL: URL,
        from connections: [AVCaptureConnection],
        error: (any Error)?
    ) {
        let fileSize = (try? FileManager.default.attributesOfItem(atPath: outputFileURL.path)[.size] as? Int) ?? nil
        videoDebugLog("[VideoRecorder] fileOutput didFinishRecordingTo: error=\(String(describing: error)), fileSize=\(String(describing: fileSize))")
        let result: URL? = error == nil ? outputFileURL : nil
        Task { @MainActor in
            if let completion = self.recordingCompletion {
                completion.resume(returning: result)
                self.recordingCompletion = nil
            } else if let result {
                // Nobody is awaiting — the recording ended on its own. Hold
                // the file so stopRecording() can still deliver it.
                videoDebugLog("[VideoRecorder] fileOutput: no awaiting caller, holding finished file")
                self.pendingFinishedURL = result
            }
        }
    }
}
#endif
