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
