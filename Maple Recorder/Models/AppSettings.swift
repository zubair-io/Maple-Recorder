import Foundation

struct AppSettings: Codable, Sendable {
    var preferredLLMProvider: LLMProvider
    var claudeAPIKey: String?
    var openAIAPIKey: String?
    var iCloudEnabled: Bool
    var chunkDurationMinutes: Int

    enum CodingKeys: String, CodingKey {
        case preferredLLMProvider = "preferred_llm_provider"
        case claudeAPIKey = "claude_api_key"
        case openAIAPIKey = "openai_api_key"
        case iCloudEnabled = "icloud_enabled"
        case chunkDurationMinutes = "chunk_duration_minutes"
    }

    init(
        preferredLLMProvider: LLMProvider = .none,
        claudeAPIKey: String? = nil,
        openAIAPIKey: String? = nil,
        iCloudEnabled: Bool = true,
        chunkDurationMinutes: Int = 30
    ) {
        self.preferredLLMProvider = preferredLLMProvider
        self.claudeAPIKey = claudeAPIKey
        self.openAIAPIKey = openAIAPIKey
        self.iCloudEnabled = iCloudEnabled
        self.chunkDurationMinutes = chunkDurationMinutes
    }
}
