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
