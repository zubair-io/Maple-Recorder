import AppIntents
import Foundation

struct StopRecordingIntent: AppIntent {
    static var title: LocalizedStringResource = "Stop Recording"
    static var description: IntentDescription = "Stops the current recording and triggers processing."
    static var openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        await MainActor.run {
            NotificationCenter.default.post(name: .stopRecordingFromIntent, object: nil)
        }
        return .result()
    }
}
