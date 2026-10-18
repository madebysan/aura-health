import Foundation
import FoundationModels
import SwiftData

/// Apple's on-device model (Foundation Models) as Aura's default assistant.
/// Questions are answered with Aura's read tools. A logging request ("Log my
/// weight at 81 kg") is read into a structured form, then saved by Aura itself
/// after the user approves, because the small model doesn't reliably call a
/// write tool on its own. Nothing leaves the iPhone. It reads text only, so PDF
/// and photo attachments stay with the cloud providers.
enum OnDeviceAssistant {
    static var isAvailable: Bool {
        if case .available = SystemLanguageModel.default.availability { return true }
        return false
    }

    /// Why the model can't run, in plain words, or nil when it can.
    static var unavailableReason: String? {
        switch SystemLanguageModel.default.availability {
        case .available:
            return nil
        case .unavailable(.deviceNotEligible):
            return "This iPhone can't run Apple Intelligence. Use your own Anthropic or OpenRouter key instead."
        case .unavailable(.appleIntelligenceNotEnabled):
            return "Turn on Apple Intelligence in the Settings app to use the on-device assistant."
        case .unavailable(.modelNotReady):
            return "Apple's on-device model is still downloading. Try again in a few minutes."
        case .unavailable:
            return "Apple's on-device model isn't available right now."
        }
    }

    @MainActor
    static func respond(
        to history: [ChatMessage],
        instructions: String,
        service: AIService,
        container: ModelContainer
    ) async throws -> String {
        let message = history.last(where: { $0.role == .user })?.content ?? ""
        let session = LanguageModelSession(tools: tools(service: service, container: container), instructions: instructions)
        do {
            if asksToLog(message), let saved = try await logRequest(message, service: service, container: container) {
                return saved
            }
            let reply = try await session.respond(to: prompt(from: history)).content
            // This session has no write tools, so any "saved" in the reply is untrue
            return checked(reply, savedSomething: false)
        } catch let error as LanguageModelSession.GenerationError {
            switch error {
            case .exceededContextWindowSize:
                return "This conversation is too long for the on-device model. Start a new chat and ask again."
            case .guardrailViolation, .refusal:
                return "The on-device model couldn't answer that. Try asking another way."
            case .unsupportedLanguageOrLocale:
                return "The on-device model doesn't support this language yet."
            default:
                throw error
            }
        }
    }

    /// The last few turns, trimmed to fit the small context window, then the new message.
    static func prompt(from history: [ChatMessage]) -> String {
        let turns = history.filter { $0.role == .user || $0.role == .assistant }
        guard let last = turns.last else { return "" }
        let earlier = turns.dropLast().suffix(4).map { message in
            let who = message.role == .user ? "User" : "Aura"
            return "\(who): \(message.content.prefix(400))"
        }
        guard !earlier.isEmpty else { return last.content }
        return "Conversation so far:\n" + earlier.joined(separator: "\n") + "\n\nNew message: " + last.content
    }

    /// The small model can say "logged" without calling a tool. If a reply claims a
    /// save and no saving tool ran, say plainly that nothing was saved.
    static func checked(_ reply: String, savedSomething: Bool) -> String {
        let claimsSave = reply.range(of: #"\b(logged|saved|added|recorded)\b"#, options: [.regularExpression, .caseInsensitive]) != nil
        guard claimsSave && !savedSomething else { return reply }
        return "Nothing was saved. Try again with the value and unit, such as \u{201C}Log weight 81 kg\u{201D}, or add it with + on Vitals or Habits."
    }

    /// Whether a message reads like a request to save something.
    static func asksToLog(_ message: String) -> Bool {
        let pattern = #"\b(log|logged|add|added|record|recorded|save|track|took|taken|did|done|completed|finished|weighed)\b"#
        return message.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }

    // MARK: - Logging

    /// Reads a logging request into a form and saves it through Aura's own tool,
    /// with the usual approval. Returns nil when the message isn't a request to log.
    @MainActor
    private static func logRequest(_ message: String, service: AIService, container: ModelContainer) async throws -> String? {
        let today = Date().formatted(.iso8601.year().month().day())
        let reader = LanguageModelSession(instructions: "Read what the user wants to save in a health app. Today is \(today). If they are only asking a question, the kind is none.")
        let intent = try await reader.respond(to: message, generating: LogIntent.self).content

        var input: [String: any Sendable] = [:]
        let tool: String
        switch intent.kind {
        case "measurement":
            guard let metric = intent.metric, let value = intent.value else { return nil }
            tool = "add_measurement"
            input = ["metric": metric, "value": value]
            if let value2 = intent.value2 { input["value2"] = value2 }
            if let unit = intent.unit, !unit.isEmpty { input["unit"] = unit }
        case "habit":
            guard let habitName = intent.habitName, !habitName.isEmpty else { return nil }
            tool = "log_habit"
            input = ["habitName": habitName]
        default:
            return nil
        }
        if let date = intent.date, !date.isEmpty { input["date"] = date }

        let result = await service.executeTool(name: tool, input: input, context: container.mainContext)
        return confirmation(for: result)
    }

    /// Aura's own wording for what the save tool reported.
    static func confirmation(for result: String) -> String {
        if result.hasPrefix("Added: ") || result.hasPrefix("Logged: ") {
            let detail = result.drop(while: { $0 != " " }).dropFirst().replacingOccurrences(of: " = ", with: " ")
            return "Saved: \(detail)."
        }
        if result.hasPrefix("The user did not approve") { return "Nothing was saved." }
        let reason = result.hasPrefix("Error: ") ? String(result.dropFirst(7)) : result
        return "Nothing was saved. " + reason.prefix(1).uppercased() + reason.dropFirst()
    }

    @Generable
    struct LogIntent {
        @Guide(description: "measurement to save a vital reading, habit if the user says they did a habit, none if nothing should be saved", .anyOf(["measurement", "habit", "none"]))
        var kind: String
        @Guide(description: "For a measurement: weight, heartRate, bloodPressure, sleepDuration, steps, hrv, spo2, calories or activeMinutes")
        var metric: String?
        @Guide(description: "The number the user gave")
        var value: Double?
        @Guide(description: "Diastolic, only for blood pressure")
        var value2: Double?
        @Guide(description: "The unit the user gave, such as kg, lbs, bpm, C or F")
        var unit: String?
        @Guide(description: "For a habit: its name")
        var habitName: String?
        @Guide(description: "YYYY-MM-DD if the user named a day")
        var date: String?
    }

    // MARK: - Tools

    private static func tools(service: AIService, container: ModelContainer) -> [any Tool] {
        [
            AuraTool<SummaryArgs>(name: "get_health_summary",
                                  description: "Overview of latest vitals, conditions, medications, habits and recent lab results.",
                                  service: service, container: container) { _ in [:] },
            AuraTool<VitalsArgs>(name: "get_vitals",
                                 description: "Recent vital measurements such as weight, heart rate, sleep or steps.",
                                 service: service, container: container) { args in
                var input: [String: any Sendable] = [:]
                if let metric = args.metric { input["metric"] = metric }
                if let days = args.days { input["days"] = days }
                return input
            },
            AuraTool<LabArgs>(name: "get_biomarkers",
                              description: "Lab results, filtered by marker name or body system.",
                              service: service, container: container) { args in
                var input: [String: any Sendable] = [:]
                if let marker = args.marker { input["marker"] = marker }
                if let system = args.system { input["system"] = system }
                return input
            },
            // A no-argument tool: the small model calls it more reliably than a filter flag
            AuraTool<SummaryArgs>(name: "get_lab_flags",
                                  description: "Latest lab results that are outside or near their reference range.",
                                  service: service, container: container) { _ in ["flaggedOnly": true] },
            AuraTool<SummaryArgs>(name: "get_medications", description: "Active medications and supplements.",
                                  service: service, container: container) { _ in [:] },
            AuraTool<SummaryArgs>(name: "get_conditions", description: "Health conditions and their status.",
                                  service: service, container: container) { _ in [:] },
            AuraTool<SummaryArgs>(name: "get_habits", description: "Habits with recent completion.",
                                  service: service, container: container) { _ in [:] },
        ]
    }

    /// One of Aura's tools for the on-device model. It hops to the main actor and
    /// runs the same code (and the same approval prompt) as the cloud providers.
    struct AuraTool<Arguments: Generable & Sendable>: Tool {
        let name: String
        let description: String
        let service: AIService
        let container: ModelContainer
        let makeInput: @Sendable (Arguments) -> [String: any Sendable]

        init(name: String, description: String, service: AIService, container: ModelContainer,
             makeInput: @escaping @Sendable (Arguments) -> [String: any Sendable]) {
            self.name = name
            self.description = description
            self.service = service
            self.container = container
            self.makeInput = makeInput
        }

        @concurrent
        func call(arguments: Arguments) async throws -> String {
            await OnDeviceAssistant.run(name, input: makeInput(arguments), service: service, container: container)
        }
    }

    @MainActor
    private static func run(_ name: String, input: [String: any Sendable], service: AIService, container: ModelContainer) async -> String {
        // get_lab_flags is get_biomarkers with the flagged-only filter
        let auraName = name == "get_lab_flags" ? "get_biomarkers" : name
        return await service.executeTool(name: auraName, input: input, context: container.mainContext)
    }

    @Generable
    struct SummaryArgs {
        @Guide(description: "Leave empty")
        var note: String?
    }

    @Generable
    struct VitalsArgs {
        @Guide(description: "One of: weight, heartRate, bloodPressure, sleepDuration, steps, hrv, spo2, skinTemp, calories, activeMinutes. Omit for all.")
        var metric: String?
        @Guide(description: "Days to look back, 1 to 90. Default 7.")
        var days: Int?
    }

    @Generable
    struct LabArgs {
        @Guide(description: "Marker name, such as LDL Cholesterol or TSH")
        var marker: String?
        @Guide(description: "Body system: Heart, Metabolic, Liver, Kidney, Thyroid, Blood, Hormones, Inflammation or Vitamins")
        var system: String?
    }
}
