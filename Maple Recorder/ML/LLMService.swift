#if !os(watchOS)
import Foundation

protocol LLMService: Sendable {
    var isAvailable: Bool { get }
    func generate(systemPrompt: String, userMessage: String) async throws -> String
}

enum LLMServiceError: Error, LocalizedError {
    case notAvailable
    case invalidResponse
    case apiError(String)
    case networkError(Error)

    var errorDescription: String? {
        switch self {
        case .notAvailable: "LLM service is not available"
        case .invalidResponse: "Invalid response from LLM"
        case .apiError(let message): "API error: \(message)"
        case .networkError(let error): "Network error: \(error.localizedDescription)"
        }
    }
}

// MARK: - Apple Foundation Models

import FoundationModels

struct AppleFoundationModelsService: LLMService {
    var isAvailable: Bool {
        SystemLanguageModel.default.isAvailable
    }

    func generate(systemPrompt: String, userMessage: String) async throws -> String {
        guard isAvailable else { throw LLMServiceError.notAvailable }
        let session = LanguageModelSession(instructions: systemPrompt)
        let response = try await session.respond(to: userMessage)
        return response.content
    }
}

// MARK: - Claude (Anthropic API)

struct ClaudeService: LLMService {
    let apiKey: String

    var isAvailable: Bool { !apiKey.isEmpty }

    func generate(systemPrompt: String, userMessage: String) async throws -> String {
        let url = URL(string: "https://api.anthropic.com/v1/messages")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        let body: [String: Any] = [
            "model": "claude-sonnet-4-5-20250929",
            "max_tokens": 4096,
            "system": systemPrompt,
            "messages": [
                ["role": "user", "content": userMessage]
            ],
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw LLMServiceError.invalidResponse
        }
        guard httpResponse.statusCode == 200 else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw LLMServiceError.apiError("HTTP \(httpResponse.statusCode): \(errorBody)")
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let content = json?["content"] as? [[String: Any]],
              let text = content.first?["text"] as? String else {
            throw LLMServiceError.invalidResponse
        }

        return text
    }
}

// MARK: - OpenAI

struct OpenAIService: LLMService {
    let apiKey: String

    var isAvailable: Bool { !apiKey.isEmpty }

    func generate(systemPrompt: String, userMessage: String) async throws -> String {
        let url = URL(string: "https://api.openai.com/v1/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let body: [String: Any] = [
            "model": "gpt-4o",
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": userMessage],
            ],
            "max_tokens": 4096,
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw LLMServiceError.invalidResponse
        }
        guard httpResponse.statusCode == 200 else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw LLMServiceError.apiError("HTTP \(httpResponse.statusCode): \(errorBody)")
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let choices = json?["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let text = message["content"] as? String else {
            throw LLMServiceError.invalidResponse
        }

        return text
    }
}

// MARK: - Factory

enum LLMServiceFactory {
    static func service(for provider: LLMProvider) -> (any LLMService)? {
        switch provider {
        case .appleFoundationModels:
            return AppleFoundationModelsService()
        case .claude:
            guard let key = KeychainManager.load(key: .claudeAPIKey), !key.isEmpty else { return nil }
            return ClaudeService(apiKey: key)
        case .openai:
            guard let key = KeychainManager.load(key: .openAIAPIKey), !key.isEmpty else { return nil }
            return OpenAIService(apiKey: key)
        case .none:
            return nil
        }
    }
}
#endif
