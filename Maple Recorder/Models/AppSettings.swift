import Foundation

struct AppSettings: Codable, Sendable {
    var preferredLLMProvider: LLMProvider
    var claudeAPIKey: String?
    var openAIAPIKey: String?
    var iCloudEnabled: Bool
    var chunkDurationMinutes: Int
    var autoStopOnSilenceEnabled: Bool
    var autoStopSilenceMinutes: Int
    var endCallDetectionEnabled: Bool

    enum CodingKeys: String, CodingKey {
        case preferredLLMProvider = "preferred_llm_provider"
        case claudeAPIKey = "claude_api_key"
        case openAIAPIKey = "openai_api_key"
        case iCloudEnabled = "icloud_enabled"
        case chunkDurationMinutes = "chunk_duration_minutes"
        case autoStopOnSilenceEnabled = "auto_stop_on_silence_enabled"
        case autoStopSilenceMinutes = "auto_stop_silence_minutes"
        case endCallDetectionEnabled = "end_call_detection_enabled"
    }

    init(
        preferredLLMProvider: LLMProvider = .none,
        claudeAPIKey: String? = nil,
        openAIAPIKey: String? = nil,
        iCloudEnabled: Bool = true,
        chunkDurationMinutes: Int = 30,
        autoStopOnSilenceEnabled: Bool = true,
        autoStopSilenceMinutes: Int = 5,
        endCallDetectionEnabled: Bool = true
    ) {
        self.preferredLLMProvider = preferredLLMProvider
        self.claudeAPIKey = claudeAPIKey
        self.openAIAPIKey = openAIAPIKey
        self.iCloudEnabled = iCloudEnabled
        self.chunkDurationMinutes = chunkDurationMinutes
        self.autoStopOnSilenceEnabled = autoStopOnSilenceEnabled
        self.autoStopSilenceMinutes = autoStopSilenceMinutes
        self.endCallDetectionEnabled = endCallDetectionEnabled
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        preferredLLMProvider = try container.decode(LLMProvider.self, forKey: .preferredLLMProvider)
        claudeAPIKey = try container.decodeIfPresent(String.self, forKey: .claudeAPIKey)
        openAIAPIKey = try container.decodeIfPresent(String.self, forKey: .openAIAPIKey)
        iCloudEnabled = try container.decode(Bool.self, forKey: .iCloudEnabled)
        chunkDurationMinutes = try container.decode(Int.self, forKey: .chunkDurationMinutes)
        autoStopOnSilenceEnabled = try container.decodeIfPresent(Bool.self, forKey: .autoStopOnSilenceEnabled) ?? true
        autoStopSilenceMinutes = try container.decodeIfPresent(Int.self, forKey: .autoStopSilenceMinutes) ?? 5
        endCallDetectionEnabled = try container.decodeIfPresent(Bool.self, forKey: .endCallDetectionEnabled) ?? true
    }
}
