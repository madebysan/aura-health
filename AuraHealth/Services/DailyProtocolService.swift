import Foundation
import SwiftData
import os

private let logger = Logger(subsystem: "com.santiagoalonso.aurahealth", category: "DailyProtocol")

/// Generates a personalized daily health protocol by sending the user's
/// real health context to Claude and getting back specific, actionable habits.
@Observable
@MainActor
final class DailyProtocolService {
    var isGenerating = false
    var lastError: String?

    private static let apiURL = "https://api.anthropic.com/v1/messages"
    private static let model = "claude-sonnet-4-6"

    private var apiKey: String {
        KeychainService.getValue(for: "claude-api-key") ?? ""
    }

    var hasAPIKey: Bool { !apiKey.isEmpty }

    // MARK: - Generate Today's Protocol

    /// Check if we need to generate today's protocol and do it if so.
    func generateIfNeeded(context: ModelContext) async {
        guard hasAPIKey else { return }

        let today = Calendar.current.startOfDay(for: Date())

        // Check if we already generated for today
        let metaDescriptor = FetchDescriptor<ProtocolMeta>(
            predicate: #Predicate { $0.forDate == today }
        )
        if let existing = try? context.fetch(metaDescriptor), !existing.isEmpty {
            // Already generated today — check if data changed
            let currentHash = buildContextHash(context: context)
            if existing.first?.contextHash == currentHash {
                return // Data hasn't changed, skip
            }
            // Data changed — clear old protocol and regenerate
            clearTodayProtocol(context: context)
        }

        await generate(context: context)
    }

    /// Force regenerate today's protocol (user-triggered refresh).
    func regenerate(context: ModelContext) async {
        clearTodayProtocol(context: context)
        await generate(context: context)
    }

    private func generate(context: ModelContext) async {
        guard hasAPIKey else {
            lastError = "Claude API key required for smart habits"
            return
        }

        isGenerating = true
        lastError = nil

        do {
            let healthContext = buildHealthContext(context: context)
            let habits = try await callClaude(healthContext: healthContext)

            let today = Calendar.current.startOfDay(for: Date())

            // Insert smart habits
            for (index, habit) in habits.enumerated() {
                let section = parseGridSection(habit.timing)
                context.insert(SmartHabit(
                    date: today,
                    name: habit.name,
                    reason: habit.reason,
                    gridSection: section,
                    priority: index
                ))
            }

            // Record that we generated
            let hash = buildContextHash(context: context)
            context.insert(ProtocolMeta(forDate: today, contextHash: hash))

            try? context.save()
            logger.notice("[DailyProtocol] Generated \(habits.count) smart habits")
        } catch {
            lastError = "Failed to generate: \(error.localizedDescription)"
            logger.error("[DailyProtocol] Generation failed: \(error.localizedDescription)")
        }

        isGenerating = false
    }

    private func clearTodayProtocol(context: ModelContext) {
        let today = Calendar.current.startOfDay(for: Date())
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: today)!

        // Delete today's smart habits
        let habitDescriptor = FetchDescriptor<SmartHabit>(
            predicate: #Predicate { $0.date >= today && $0.date < tomorrow }
        )
        if let existing = try? context.fetch(habitDescriptor) {
            for habit in existing { context.delete(habit) }
        }

        // Delete today's meta
        let metaDescriptor = FetchDescriptor<ProtocolMeta>(
            predicate: #Predicate { $0.forDate >= today && $0.forDate < tomorrow }
        )
        if let existing = try? context.fetch(metaDescriptor) {
            for meta in existing { context.delete(meta) }
        }
    }

    // Also clean up old protocol data (older than 7 days)
    func cleanupOldProtocols(context: ModelContext) {
        let cutoff = Calendar.current.date(byAdding: .day, value: -7, to: Date())!
        let habitDescriptor = FetchDescriptor<SmartHabit>(
            predicate: #Predicate { $0.date < cutoff }
        )
        if let old = try? context.fetch(habitDescriptor) {
            for h in old { context.delete(h) }
        }
        let metaDescriptor = FetchDescriptor<ProtocolMeta>(
            predicate: #Predicate { $0.forDate < cutoff }
        )
        if let old = try? context.fetch(metaDescriptor) {
            for m in old { context.delete(m) }
        }
    }

    // MARK: - Build Health Context

    /// Gather all relevant health data into a text summary for Claude.
    private func buildHealthContext(context: ModelContext) -> String {
        var sections: [String] = []
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())

        // 1. Last night's sleep + today's vitals
        let threeDaysAgo = cal.date(byAdding: .day, value: -3, to: today)!
        let vitalDescriptor = FetchDescriptor<Measurement>(
            predicate: #Predicate { $0.timestamp >= threeDaysAgo },
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        if let vitals = try? context.fetch(vitalDescriptor), !vitals.isEmpty {
            var vitalLines: [String] = []
            let grouped = Dictionary(grouping: vitals, by: { $0.metricType })
            for (type, measurements) in grouped.sorted(by: { $0.key.rawValue < $1.key.rawValue }) {
                if let latest = measurements.first {
                    let trend: String
                    if measurements.count >= 3 {
                        let recent = measurements.prefix(3).map(\.value)
                        let avg = recent.reduce(0, +) / Double(recent.count)
                        trend = latest.value > avg * 1.05 ? " (trending up)" : latest.value < avg * 0.95 ? " (trending down)" : ""
                    } else { trend = "" }
                    vitalLines.append("- \(type.displayName): \(latest.displayValue) \(type.unit)\(trend)")
                }
            }
            if !vitalLines.isEmpty {
                sections.append("RECENT VITALS (last 3 days):\n\(vitalLines.joined(separator: "\n"))")
            }
        }

        // 2. Biomarkers (most recent results, flag out-of-range)
        let bioDescriptor = FetchDescriptor<Biomarker>(
            sortBy: [SortDescriptor(\.testDate, order: .reverse)]
        )
        if let biomarkers = try? context.fetch(bioDescriptor), !biomarkers.isEmpty {
            // Get most recent result per marker
            var seen = Set<String>()
            var bioLines: [String] = []
            for bio in biomarkers {
                guard !seen.contains(bio.marker) else { continue }
                seen.insert(bio.marker)
                let statusEmoji = bio.status == .abnormal ? "!!!" : bio.status == .borderline ? "!" : ""
                let refRange = [bio.refMin, bio.refMax].compactMap { $0 }.isEmpty
                    ? "" : " (ref: \(bio.refMin.map { String(format: "%.1f", $0) } ?? "?")–\(bio.refMax.map { String(format: "%.1f", $0) } ?? "?"))"
                bioLines.append("- \(bio.marker): \(String(format: "%.1f", bio.value)) \(bio.unit)\(refRange) \(statusEmoji)")
            }
            if !bioLines.isEmpty {
                sections.append("LATEST BIOMARKERS:\n\(bioLines.prefix(20).joined(separator: "\n"))")
            }
        }

        // 3. Active medications
        let medDescriptor = FetchDescriptor<Medication>(
            predicate: #Predicate { $0.active == true }
        )
        if let meds = try? context.fetch(medDescriptor), !meds.isEmpty {
            let medLines = meds.map { "- \($0.name) \($0.dosage) (\($0.timing.displayName), \($0.frequency.displayName))" }
            sections.append("ACTIVE MEDICATIONS:\n\(medLines.joined(separator: "\n"))")
        }

        // 4. Active conditions
        let resolvedRaw = ConditionStatus.resolved.rawValue
        let condDescriptor = FetchDescriptor<Condition>(
            predicate: #Predicate { $0.status.rawValue != resolvedRaw }
        )
        if let conditions = try? context.fetch(condDescriptor), !conditions.isEmpty {
            let condLines = conditions.map { "- \($0.name) (\($0.status.displayName))" }
            sections.append("ACTIVE CONDITIONS:\n\(condLines.joined(separator: "\n"))")
        }

        // 5. Current manual habits and yesterday's adherence
        let habitDescriptor = FetchDescriptor<Habit>(
            predicate: #Predicate { $0.active == true }
        )
        if let habits = try? context.fetch(habitDescriptor), !habits.isEmpty {
            let yesterday = cal.date(byAdding: .day, value: -1, to: today)!
            let habitLines = habits.map { habit -> String in
                let yesterdayLog = habit.logs.first { cal.startOfDay(for: $0.date) == yesterday }
                let status = yesterdayLog?.done == true ? "done" : "missed"
                return "- \(habit.name) (\(habit.gridSection.displayName)) — yesterday: \(status)"
            }
            sections.append("MANUAL HABITS (with yesterday's adherence):\n\(habitLines.joined(separator: "\n"))")
        }

        // 6. Diet plan if any
        let dietDescriptor = FetchDescriptor<DietPlan>(
            sortBy: [SortDescriptor(\.startDate, order: .reverse)]
        )
        if let diets = try? context.fetch(dietDescriptor), let diet = diets.first {
            sections.append("CURRENT DIET: \(diet.dietType)")
        }

        return sections.joined(separator: "\n\n")
    }

    /// Simple hash of key health metrics to detect data changes.
    private func buildContextHash(context: ModelContext) -> String {
        let today = Calendar.current.startOfDay(for: Date())
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: today)!

        // Hash based on: latest vital timestamps + biomarker count + med count
        let vitalDesc = FetchDescriptor<Measurement>(
            predicate: #Predicate { $0.timestamp >= yesterday },
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        let vitalCount = (try? context.fetchCount(vitalDesc)) ?? 0

        let bioCount = (try? context.fetchCount(FetchDescriptor<Biomarker>())) ?? 0
        let medCount = (try? context.fetchCount(FetchDescriptor<Medication>(predicate: #Predicate { $0.active == true }))) ?? 0

        return "\(vitalCount)-\(bioCount)-\(medCount)-\(today.timeIntervalSince1970)"
    }

    // MARK: - Claude API Call

    struct GeneratedHabit: Codable {
        let name: String
        let reason: String
        let timing: String  // "morning", "afternoon", "evening", "night"
    }

    private func callClaude(healthContext: String) async throws -> [GeneratedHabit] {
        guard let url = URL(string: Self.apiURL) else { throw ProtocolError.invalidURL }

        let systemPrompt = """
        You are a health protocol generator inside the Aura Health app. Your job is to create a personalized daily action list based on the user's real health data.

        RULES:
        - Generate 5-8 specific, actionable habits for TODAY
        - Each habit must be something the user can DO today, not a vague goal
        - Be SPECIFIC: "Walk 30 min after lunch" not "exercise more". "Eat salmon or sardines for dinner" not "eat healthy"
        - Consider TIME OF DAY: assign each habit to morning, afternoon, evening, or night
        - Consider INTERACTIONS: don't suggest fasted cardio if they take metformin with food. Don't suggest caffeine if sleep is poor
        - Look at TRENDS: if sleep is declining, prioritize recovery. If a biomarker is improving, acknowledge progress
        - Reference REAL DATA: mention actual values ("Your HRV dropped to 22ms") not generic statements
        - If biomarkers are out of range, suggest habits that specifically address them
        - If medications have timing requirements, remind about optimal timing
        - Don't duplicate the user's existing manual habits — complement them
        - Don't suggest things they're already doing well (check yesterday's adherence)
        - Include the WHY in the reason field — the user should understand why each habit matters for them specifically
        - You are NOT a doctor. Frame suggestions as wellness habits, not medical advice
        - NEVER say "consult your doctor" in habit names — that's for the reason field if needed

        Respond with ONLY a JSON array. No other text. Format:
        [{"name": "habit description", "reason": "why this matters for you specifically", "timing": "morning|afternoon|evening|night"}]
        """

        let userMessage = """
        Generate my daily health protocol based on this data:

        \(healthContext)

        Today is \(Date().formatted(date: .complete, time: .omitted)).
        """

        let requestBody: [String: Any] = [
            "model": Self.model,
            "max_tokens": 2048,
            "system": systemPrompt,
            "messages": [
                ["role": "user", "content": userMessage]
            ]
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? "Unknown"
            throw ProtocolError.apiError(body)
        }

        // Parse Claude's response
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = json["content"] as? [[String: Any]],
              let textBlock = content.first(where: { $0["type"] as? String == "text" }),
              let text = textBlock["text"] as? String else {
            throw ProtocolError.parseError
        }

        // Extract JSON array from response (Claude might wrap it in markdown code blocks)
        let cleanJSON = text
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let jsonData = cleanJSON.data(using: .utf8) else {
            throw ProtocolError.parseError
        }

        let habits = try JSONDecoder().decode([GeneratedHabit].self, from: jsonData)
        return habits
    }

    // MARK: - Helpers

    private func parseGridSection(_ timing: String) -> GridSection {
        switch timing.lowercased() {
        case "morning": return .morning
        case "afternoon": return .afternoon
        case "evening": return .evening
        case "night": return .night
        default: return .morning
        }
    }
}

enum ProtocolError: LocalizedError {
    case invalidURL
    case apiError(String)
    case parseError

    var errorDescription: String? {
        switch self {
        case .invalidURL: "Invalid API URL"
        case .apiError(let msg): "API error: \(msg)"
        case .parseError: "Could not parse protocol response"
        }
    }
}
