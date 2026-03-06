import Foundation
import SwiftData

/// Claude API integration for the health chat assistant
@Observable
@MainActor
final class ClaudeService {
    var isResponding = false

    private var apiKey: String {
        KeychainService.getValue(for: "claude-api-key") ?? ""
    }

    var hasAPIKey: Bool {
        !apiKey.isEmpty
    }

    private static let apiURL = "https://api.anthropic.com/v1/messages"
    private static let model = "claude-sonnet-4-20250514"

    // MARK: - Send Message

    func sendMessage(
        _ userMessage: String,
        conversationHistory: [ChatMessage],
        healthContext: HealthContext
    ) async throws -> String {
        guard hasAPIKey else {
            throw ClaudeError.noAPIKey
        }

        isResponding = true
        defer { isResponding = false }

        let systemPrompt = buildSystemPrompt(context: healthContext)

        // Build messages array (last 20 messages for context window)
        var messages: [[String: String]] = []
        for msg in conversationHistory.suffix(20) {
            if msg.role == .user || msg.role == .assistant {
                messages.append([
                    "role": msg.role.rawValue,
                    "content": msg.content
                ])
            }
        }
        messages.append(["role": "user", "content": userMessage])

        let requestBody: [String: Any] = [
            "model": Self.model,
            "max_tokens": 2048,
            "system": systemPrompt,
            "messages": messages
        ]

        guard let url = URL(string: Self.apiURL) else {
            throw ClaudeError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ClaudeError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw ClaudeError.apiError(statusCode: httpResponse.statusCode, message: errorBody)
        }

        let decoded = try JSONDecoder().decode(ClaudeResponse.self, from: data)
        return decoded.content.first?.text ?? "No response"
    }

    // MARK: - System Prompt

    private func buildSystemPrompt(context: HealthContext) -> String {
        var prompt = """
        You are a helpful health assistant inside the Aura Health app. You help the user understand their health data, log new measurements, and provide actionable insights.

        IMPORTANT: You are NOT a doctor. Always recommend consulting a healthcare professional for medical decisions.

        The user's current health data:

        """

        // Latest vitals
        if !context.latestVitals.isEmpty {
            prompt += "\n## Latest Vitals\n"
            for (metric, value) in context.latestVitals {
                prompt += "- \(metric): \(value)\n"
            }
        }

        // Active medications
        if !context.medications.isEmpty {
            prompt += "\n## Active Medications\n"
            for med in context.medications {
                prompt += "- \(med)\n"
            }
        }

        // Active conditions
        if !context.conditions.isEmpty {
            prompt += "\n## Health Conditions\n"
            for condition in context.conditions {
                prompt += "- \(condition)\n"
            }
        }

        // Recent biomarkers
        if !context.recentBiomarkers.isEmpty {
            prompt += "\n## Recent Lab Results\n"
            for marker in context.recentBiomarkers {
                prompt += "- \(marker)\n"
            }
        }

        prompt += """

        ## Guidelines
        - Be concise and actionable
        - Reference specific data points when relevant
        - Flag concerning trends proactively
        - If the user describes symptoms, suggest relevant biomarkers to track
        - If the user wants to log data (e.g., "weight 180 lbs", "took my meds"), acknowledge and confirm
        - Use plain language, avoid medical jargon
        """

        return prompt
    }

    // MARK: - Build Health Context

    static func buildContext(from context: ModelContext) -> HealthContext {
        var healthContext = HealthContext()

        // Latest vitals
        for type in MetricType.allCases {
            let typeRaw = type.rawValue
            let descriptor = FetchDescriptor<Measurement>(
                predicate: #Predicate { $0.metricType.rawValue == typeRaw },
                sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
            )
            var limited = descriptor
            limited.fetchLimit = 1
            if let latest = try? context.fetch(limited).first {
                healthContext.latestVitals[type.displayName] = "\(latest.displayValue) \(type.unit)"
            }
        }

        // Active medications
        let medDescriptor = FetchDescriptor<Medication>(
            predicate: #Predicate { $0.active }
        )
        if let meds = try? context.fetch(medDescriptor) {
            healthContext.medications = meds.map { "\($0.name) \($0.dosage) (\($0.frequency.displayName))" }
        }

        // Active conditions
        let condDescriptor = FetchDescriptor<Condition>()
        if let conditions = try? context.fetch(condDescriptor) {
            healthContext.conditions = conditions.map { "\($0.name) (\($0.status.displayName))" }
        }

        // Recent biomarkers (last 3 months)
        let threeMonthsAgo = Calendar.current.date(byAdding: .month, value: -3, to: Date())!
        let bioDescriptor = FetchDescriptor<Biomarker>(
            predicate: #Predicate { $0.testDate >= threeMonthsAgo },
            sortBy: [SortDescriptor(\.testDate, order: .reverse)]
        )
        if let biomarkers = try? context.fetch(bioDescriptor) {
            healthContext.recentBiomarkers = biomarkers.map {
                "\($0.marker): \(String(format: "%.1f", $0.value)) \($0.unit) [\($0.status.displayName)]"
            }
        }

        return healthContext
    }
}

// MARK: - Models

struct HealthContext {
    var latestVitals: [String: String] = [:]
    var medications: [String] = []
    var conditions: [String] = []
    var recentBiomarkers: [String] = []
}

enum ClaudeError: LocalizedError {
    case noAPIKey
    case invalidURL
    case invalidResponse
    case apiError(statusCode: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .noAPIKey: "No API key configured. Add your Claude API key in Settings."
        case .invalidURL: "Invalid API URL."
        case .invalidResponse: "Invalid response from server."
        case .apiError(let code, let message): "API error (\(code)): \(message)"
        }
    }
}

private struct ClaudeResponse: Codable {
    let content: [ContentBlock]

    struct ContentBlock: Codable {
        let type: String
        let text: String?
    }
}
