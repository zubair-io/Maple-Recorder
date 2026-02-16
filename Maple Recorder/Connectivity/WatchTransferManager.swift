#if os(watchOS)
import Foundation
import Observation
import WatchConnectivity

/// Watch-side manager: sends recorded audio files to the paired iPhone for processing.
@Observable
final class WatchTransferManager: NSObject, WCSessionDelegate, @unchecked Sendable {
    var isTransferring = false
    var transferProgress: Double = 0
    var lastTransferError: String?
    var isPhoneReachable = false

    private var activeTransfers: [WCSessionFileTransfer] = []

    override init() {
        super.init()
        if WCSession.isSupported() {
            let session = WCSession.default
            session.delegate = self
            session.activate()
        }
    }

    /// Transfer a recorded audio file to the iPhone for processing.
    func transferRecording(fileURL: URL, metadata: [String: Any]) {
        guard WCSession.default.activationState == .activated else {
            lastTransferError = "Watch session not active"
            return
        }

        isTransferring = true
        transferProgress = 0
        lastTransferError = nil

        let transfer = WCSession.default.transferFile(fileURL, metadata: metadata)
        activeTransfers.append(transfer)

        // Monitor progress
        Task { @MainActor [weak self] in
            guard let self else { return }
            while self.isTransferring {
                try? await Task.sleep(for: .milliseconds(500))
                if let progress = self.activeTransfers.first?.progress {
                    self.transferProgress = progress.fractionCompleted
                }
            }
        }
    }

    // MARK: - WCSessionDelegate

    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        Task { @MainActor [weak self] in
            self?.isPhoneReachable = session.isReachable
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor [weak self] in
            self?.isPhoneReachable = session.isReachable
        }
    }

    nonisolated func session(_ session: WCSession, didFinish fileTransfer: WCSessionFileTransfer, error: Error?) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.activeTransfers.removeAll { $0 === fileTransfer }
            if self.activeTransfers.isEmpty {
                self.isTransferring = false
                self.transferProgress = 1.0
            }
            if let error {
                self.lastTransferError = error.localizedDescription
            }
        }
    }
}
#endif
