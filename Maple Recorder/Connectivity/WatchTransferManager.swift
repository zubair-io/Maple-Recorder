#if os(watchOS)
import Foundation
import Observation
import WatchConnectivity

/// Watch-side manager: sends recorded audio files to the paired iPhone for processing.
///
/// Delivery is tracked by recording UUID in UserDefaults so recordings aren't
/// re-queued after a successful hand-off, and un-delivered recordings can be
/// retried on next launch or via manual sync.
@Observable
final class WatchTransferManager: NSObject, WCSessionDelegate, @unchecked Sendable {
    var isTransferring = false
    var transferProgress: Double = 0
    var lastTransferError: String?
    var isPhoneReachable = false
    var pendingCount = 0

    private let deliveredKey = "maple.watch.deliveredRecordingIds"
    private var activeTransfers: [WCSessionFileTransfer] = []
    /// Maps transfer → recording UUID so we can mark delivered on finish.
    private var transferToRecordingId: [ObjectIdentifier: String] = [:]
    /// Recording IDs currently in-flight in this process — avoids double-queue.
    private var inFlightIds: Set<String> = []

    override init() {
        super.init()
        if WCSession.isSupported() {
            let session = WCSession.default
            session.delegate = self
            session.activate()

            // Re-adopt any transfers the OS kept alive across app launches so
            // we can surface progress and mark delivered on finish.
            for transfer in session.outstandingFileTransfers {
                let id = (transfer.file.metadata?["recordingId"] as? String) ?? ""
                if !id.isEmpty {
                    transferToRecordingId[ObjectIdentifier(transfer)] = id
                    inFlightIds.insert(id)
                }
                activeTransfers.append(transfer)
            }
            if !activeTransfers.isEmpty {
                isTransferring = true
                startProgressMonitor()
            }
        }
    }

    // MARK: - Public API

    /// Queue a single recording for transfer. Safe to call repeatedly — already
    /// delivered or in-flight recordings are skipped.
    func transferRecording(fileURL: URL, recordingId: UUID, title: String) {
        enqueue(fileURL: fileURL, recordingId: recordingId.uuidString, title: title)
    }

    /// Scan the given recordings and re-queue any whose audio hasn't been
    /// confirmed delivered to the phone. Call on launch and from the manual
    /// sync button.
    func syncPending(recordings: [MapleRecording]) {
        var queued = 0
        for recording in recordings {
            let idString = recording.id.uuidString
            guard !isDelivered(recordingId: idString),
                  !inFlightIds.contains(idString),
                  let fileName = recording.audioFiles.first else { continue }

            let url = StorageLocation.recordingsURL.appendingPathComponent(fileName)
            guard FileManager.default.fileExists(atPath: url.path()) else { continue }

            enqueue(fileURL: url, recordingId: idString, title: recording.title)
            queued += 1
        }
        updatePendingCount(totalRecordings: recordings.count)
        if queued > 0 {
            print("WatchTransferManager: Re-queued \(queued) pending recording(s)")
        }
    }

    /// Refresh `pendingCount` for display.
    func updatePendingCount(totalRecordings: Int) {
        let delivered = deliveredIds.count
        pendingCount = max(0, totalRecordings - delivered)
    }

    func isDelivered(recordingId: String) -> Bool {
        deliveredIds.contains(recordingId)
    }

    // MARK: - Private

    private var deliveredIds: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: deliveredKey) ?? []) }
        set { UserDefaults.standard.set(Array(newValue), forKey: deliveredKey) }
    }

    private func markDelivered(recordingId: String) {
        var ids = deliveredIds
        ids.insert(recordingId)
        deliveredIds = ids
    }

    private func enqueue(fileURL: URL, recordingId: String, title: String) {
        guard WCSession.default.activationState == .activated else {
            lastTransferError = "Watch session not active"
            return
        }
        guard !isDelivered(recordingId: recordingId), !inFlightIds.contains(recordingId) else {
            return
        }

        let metadata: [String: Any] = [
            "title": title,
            "recordingId": recordingId,
        ]
        let transfer = WCSession.default.transferFile(fileURL, metadata: metadata)
        transferToRecordingId[ObjectIdentifier(transfer)] = recordingId
        inFlightIds.insert(recordingId)
        activeTransfers.append(transfer)

        if !isTransferring {
            isTransferring = true
            transferProgress = 0
            lastTransferError = nil
            startProgressMonitor()
        }
    }

    private func startProgressMonitor() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            while self.isTransferring {
                try? await Task.sleep(for: .milliseconds(500))
                // Average progress across all active transfers for a sensible bar.
                let progresses = self.activeTransfers.map { $0.progress.fractionCompleted }
                if !progresses.isEmpty {
                    self.transferProgress = progresses.reduce(0, +) / Double(progresses.count)
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
        let key = ObjectIdentifier(fileTransfer)
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.activeTransfers.removeAll { $0 === fileTransfer }
            if let recordingId = self.transferToRecordingId.removeValue(forKey: key) {
                self.inFlightIds.remove(recordingId)
                if error == nil {
                    self.markDelivered(recordingId: recordingId)
                }
            }
            if self.activeTransfers.isEmpty {
                self.isTransferring = false
                self.transferProgress = error == nil ? 1.0 : self.transferProgress
            }
            if let error {
                self.lastTransferError = error.localizedDescription
            }
        }
    }
}
#endif
