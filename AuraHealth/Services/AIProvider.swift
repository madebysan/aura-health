import Foundation

enum AIProvider: String, Codable, CaseIterable, Identifiable {
    case anthropic
    case openRouter

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .anthropic: "Anthropic"
        case .openRouter: "OpenRouter"
        }
    }

    var keychainKey: String {
        switch self {
        case .anthropic: "anthropic-api-key"
        case .openRouter: "openrouter-api-key"
        }
    }

    var privacyPolicyURL: URL {
        switch self {
        case .anthropic: URL(string: "https://www.anthropic.com/legal/privacy")!
        case .openRouter: URL(string: "https://openrouter.ai/privacy")!
        }
    }

    var keyPlaceholder: String {
        switch self {
        case .anthropic: "sk-ant-…"
        case .openRouter: "sk-or-…"
        }
    }
}

struct AIModelOption: Identifiable, Hashable {
    let id: String
    let provider: AIProvider
    let displayName: String
    let detail: String
    let supportsTools: Bool
    let supportsImages: Bool
    let supportsPDFs: Bool
}

struct AIToolApproval: Identifiable, Equatable {
    let id = UUID()
    let toolName: String
    let summary: String
    let isDestructive: Bool
}

enum AIToolPolicy {
    private static let mutatingTools: Set<String> = [
        "add_habit",
        "log_habit",
        "add_condition",
        "add_medication",
        "add_biomarker",
        "add_measurement",
        "log_medication",
        "import_lab_results",
        "deactivate_habit",
        "deactivate_medication",
        "update_condition",
        "delete_measurement",
        "delete_biomarker",
    ]

    private static let destructiveTools: Set<String> = [
        "deactivate_habit",
        "deactivate_medication",
        "delete_measurement",
        "delete_biomarker",
    ]

    static func requiresApproval(_ toolName: String) -> Bool {
        mutatingTools.contains(toolName)
    }

    static func approval(for toolName: String, input: [String: Any]) -> AIToolApproval {
        AIToolApproval(
            toolName: toolName,
            summary: summary(for: toolName, input: input),
            isDestructive: destructiveTools.contains(toolName)
        )
    }

    private static func summary(for toolName: String, input: [String: Any]) -> String {
        let name = (input["name"] ?? input["habitName"] ?? input["medicationName"] ?? input["marker"] ?? input["metric"]) as? String
        switch toolName {
        case "add_habit": return "Add the habit \(name ?? "described in the chat") to Aura."
        case "log_habit": return "Record \(name ?? "the selected habit") for the requested date."
        case "add_condition": return "Add \(name ?? "the described condition") to Aura."
        case "add_medication": return "Add \(name ?? "the described medication") to Aura."
        case "add_biomarker": return "Add the \(name ?? "described") biomarker result to Aura."
        case "add_measurement": return "Add the \(name ?? "described") measurement to Aura."
        case "log_medication": return "Record \(name ?? "the selected medication") as taken."
        case "import_lab_results": return "Save extracted lab results from the attached file to Aura."
        case "deactivate_habit": return "Stop tracking \(name ?? "the selected habit")."
        case "deactivate_medication": return "Mark \(name ?? "the selected medication") as inactive."
        case "update_condition": return "Change \(name ?? "the selected condition") in Aura."
        case "delete_measurement": return "Delete the matching \(name ?? "measurement") from Aura."
        case "delete_biomarker": return "Delete the matching \(name ?? "biomarker result") from Aura."
        default: return "Allow this AI-requested change to Aura data."
        }
    }
}

enum AIProviderCatalog {
    static let models: [AIModelOption] = [
        AIModelOption(
            id: "claude-haiku-4-5-20251001",
            provider: .anthropic,
            displayName: "Claude Haiku",
            detail: "Fastest, lower cost",
            supportsTools: true,
            supportsImages: true,
            supportsPDFs: true
        ),
        AIModelOption(
            id: "claude-sonnet-4-6",
            provider: .anthropic,
            displayName: "Claude Sonnet",
            detail: "Balanced (recommended)",
            supportsTools: true,
            supportsImages: true,
            supportsPDFs: true
        ),
        AIModelOption(
            id: "claude-opus-4-6",
            provider: .anthropic,
            displayName: "Claude Opus",
            detail: "Most capable, higher cost",
            supportsTools: true,
            supportsImages: true,
            supportsPDFs: true
        ),
        AIModelOption(
            id: "openai/gpt-5.6-luna",
            provider: .openRouter,
            displayName: "GPT-5.6 Luna",
            detail: "Fast, capable general model",
            supportsTools: true,
            supportsImages: true,
            supportsPDFs: true
        ),
        AIModelOption(
            id: "google/gemini-3.8-flash",
            provider: .openRouter,
            displayName: "Gemini 3.8 Flash",
            detail: "Fast with long context",
            supportsTools: true,
            supportsImages: true,
            supportsPDFs: true
        ),
        AIModelOption(
            id: "anthropic/claude-sonnet-5",
            provider: .openRouter,
            displayName: "Claude Sonnet 5",
            detail: "Strong reasoning through OpenRouter",
            supportsTools: true,
            supportsImages: true,
            supportsPDFs: true
        ),
    ]

    static func models(for provider: AIProvider) -> [AIModelOption] {
        models.filter { $0.provider == provider }
    }

    static func defaultModelID(for provider: AIProvider) -> String {
        switch provider {
        case .anthropic: "claude-sonnet-4-6"
        case .openRouter: "openai/gpt-5.6-luna"
        }
    }

    static func model(id: String, provider: AIProvider) -> AIModelOption {
        models(for: provider).first(where: { $0.id == id })
            ?? models(for: provider).first(where: { $0.id == defaultModelID(for: provider) })!
    }
}

enum AIKeyStore {
    static func value(for provider: AIProvider) -> String? {
        if let value = KeychainService.getValue(for: provider.keychainKey), !value.isEmpty {
            return value
        }
        // Read legacy Anthropic keys so existing TestFlight users can opt in without retyping.
        if provider == .anthropic {
            return KeychainService.getValue(for: "claude-api-key")
        }
        return nil
    }

    @discardableResult
    static func setValue(_ value: String, for provider: AIProvider) -> Bool {
        guard KeychainService.setValue(value, for: provider.keychainKey) else { return false }
        if provider == .anthropic {
            KeychainService.deleteValue(for: "claude-api-key")
        }
        return true
    }

    static func removeValue(for provider: AIProvider) {
        KeychainService.deleteValue(for: provider.keychainKey)
        if provider == .anthropic {
            KeychainService.deleteValue(for: "claude-api-key")
        }
        AIConsentStore().revoke(for: provider)
    }
}

struct AIConsentStore {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func hasConsent(for provider: AIProvider) -> Bool {
        defaults.bool(forKey: key(for: provider))
    }

    func grant(for provider: AIProvider) {
        defaults.set(true, forKey: key(for: provider))
    }

    func revoke(for provider: AIProvider) {
        defaults.removeObject(forKey: key(for: provider))
    }

    private func key(for provider: AIProvider) -> String {
        "ai-consent-\(provider.rawValue)"
    }
}

enum AIPreferences {
    static var provider: AIProvider {
        AIProvider(rawValue: UserDefaults.standard.string(forKey: "aiProvider") ?? "") ?? .anthropic
    }

    static var modelID: String {
        let stored = UserDefaults.standard.string(forKey: "aiModel") ?? ""
        return AIProviderCatalog.model(id: stored, provider: provider).id
    }
}

enum AIRequestFactory {
    static func openRouterRequest(
        apiKey: String,
        model: String,
        messages: [[String: Any]],
        tools: [[String: Any]],
        maxTokens: Int,
        includeTools: Bool
    ) throws -> URLRequest {
        guard let url = URL(string: "https://openrouter.ai/api/v1/chat/completions") else {
            throw ClaudeError.invalidURL
        }

        var body: [String: Any] = [
            "model": model,
            "max_tokens": maxTokens,
            "messages": messages,
        ]
        if includeTools {
            body["tools"] = tools.map { ["type": "function", "function": $0] }
            body["parallel_tool_calls"] = true
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = maxTokens > 1024 ? 60 : 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("https://santiagoalonso.com", forHTTPHeaderField: "HTTP-Referer")
        request.setValue("Aura Health", forHTTPHeaderField: "X-OpenRouter-Title")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }
}

struct OpenRouterChatResponse: Decodable {
    let choices: [Choice]

    struct Choice: Decodable {
        let message: Message
    }

    struct Message: Decodable {
        let content: String?
        let toolCalls: [ToolCall]?

        private enum CodingKeys: String, CodingKey {
            case content
            case toolCalls = "tool_calls"
        }
    }

    struct ToolCall: Decodable {
        let id: String
        let type: String
        let function: Function

        struct Function: Decodable {
            let name: String
            let arguments: String
        }
    }
}
