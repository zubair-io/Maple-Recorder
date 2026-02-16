import AppIntents
import Foundation

struct StartRecordingIntent: AppIntent {
    static var title: LocalizedStringResource = "Start Recording"
    static var description: IntentDescription = "Begins a new audio recording in Maple Recorder."
    static var openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        await MainActor.run {
            NotificationCenter.default.post(name: .startRecordingFromIntent, object: nil)
        }
        return .result()
    }
}

extension Notification.Name {
    static let startRecordingFromIntent = Notification.Name("com.maple.startRecording")
    static let stopRecordingFromIntent = Notification.Name("com.maple.stopRecording")
}
