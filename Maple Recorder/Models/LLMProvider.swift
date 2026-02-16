import Foundation

enum LLMProvider: String, Codable, CaseIterable, Sendable {
    case appleFoundationModels = "apple_foundation_models"
    case claude = "claude"
    case openai = "openai"
    case none = "none"
}
