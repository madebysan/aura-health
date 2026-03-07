import Foundation
import SwiftData

/// Claude API integration with tool use for reading and modifying health data
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
    private static let model = "claude-sonnet-4-6"

    // MARK: - System Prompt (lean — no data, just behavior rules)

    private static let systemPrompt = """
    You are a concise health assistant inside the Aura Health app.

    RULES:
    - You are NOT a doctor. Always recommend consulting a healthcare professional for medical decisions.
    - Use tools to read data BEFORE answering health questions. Never guess values.
    - Use write tools ONLY when the user explicitly asks to add/log something.
    - After writing data, state exactly what was added in your response so the user can verify.
    - Be concise: use bold for key values. No filler or narration.
    - Do NOT narrate what you're doing ("Let me check..." / "I'll look up..."). Just call the tool and respond with results.
    - When using tools, call ALL needed tools in a SINGLE round. Do NOT make multiple sequential tool calls for the same type of data.
    - When showing biomarkers: include value, unit, ref range, and status.
    - For ambiguous requests, ask for clarification. Do NOT assume values.
    - Do NOT give specific medical advice, diagnoses, or treatment recommendations.
    """

    // MARK: - Tool Definitions

    private static let tools: [[String: Any]] = [
        // READ tools
        [
            "name": "get_vitals",
            "description": "Get recent vital measurements. Use when user asks about weight, heart rate, sleep, steps, etc.",
            "input_schema": [
                "type": "object",
                "properties": [
                    "metric": [
                        "type": "string",
                        "enum": ["weight", "heartRate", "sleepDuration", "sleepScore", "steps", "activeMinutes", "hrv", "recovery", "strain", "spo2", "skinTemp", "calories", "bloodPressure"],
                        "description": "Filter by metric type. Omit for all."
                    ],
                    "days": [
                        "type": "integer",
                        "description": "Days to look back (1-90). Default 7."
                    ]
                ],
                "required": [] as [String]
            ]
        ],
        [
            "name": "get_biomarkers",
            "description": "Get lab biomarker results. Use when user asks about blood work, lab results, or specific markers like cholesterol, TSH, etc.",
            "input_schema": [
                "type": "object",
                "properties": [
                    "marker": [
                        "type": "string",
                        "description": "Filter by marker name (e.g. 'Hemoglobin', 'TSH', 'cholesterol'). Strongly recommended to filter."
                    ],
                    "system": [
                        "type": "string",
                        "enum": ["Heart", "Metabolic", "Liver", "Kidney", "Thyroid", "Blood", "Hormones", "Inflammation", "Vitamins"],
                        "description": "Filter by body system. Use instead of marker for broader queries."
                    ]
                ],
                "required": [] as [String]
            ]
        ],
        [
            "name": "get_medications",
            "description": "Get active medications list.",
            "input_schema": [
                "type": "object",
                "properties": [:] as [String: Any],
                "required": [] as [String]
            ]
        ],
        [
            "name": "get_conditions",
            "description": "Get health conditions list.",
            "input_schema": [
                "type": "object",
                "properties": [:] as [String: Any],
                "required": [] as [String]
            ]
        ],
        // WRITE tools
        [
            "name": "add_biomarker",
            "description": "Add a lab result. ONLY use when user explicitly asks to add/record a biomarker value.",
            "input_schema": [
                "type": "object",
                "properties": [
                    "marker": ["type": "string", "description": "Standardized marker name (e.g. 'Total Cholesterol', 'TSH', 'Hemoglobin')"],
                    "value": ["type": "number", "description": "The numeric value"],
                    "unit": ["type": "string", "description": "Unit of measurement (e.g. 'mg/dL', 'mIU/L')"],
                    "refMin": ["type": "number", "description": "Reference range minimum (if known)"],
                    "refMax": ["type": "number", "description": "Reference range maximum (if known)"],
                    "lab": ["type": "string", "description": "Lab name (if mentioned, e.g. 'Quest', 'LabCorp')"],
                    "testDate": ["type": "string", "description": "Test date as YYYY-MM-DD. Use today if not specified."]
                ],
                "required": ["marker", "value", "unit"]
            ]
        ],
        [
            "name": "add_measurement",
            "description": "Log a vital measurement. ONLY use when user explicitly asks to log/record a measurement. Note: sleepScore, recovery, strain, skinTemp are read-only sensor metrics and cannot be logged manually.",
            "input_schema": [
                "type": "object",
                "properties": [
                    "metric": [
                        "type": "string",
                        "enum": ["weight", "heartRate", "sleepDuration", "steps", "activeMinutes", "hrv", "spo2", "calories", "bloodPressure"],
                        "description": "Metric type"
                    ],
                    "value": ["type": "number", "description": "The numeric value"],
                    "value2": ["type": "number", "description": "Second value (only for bloodPressure: diastolic)"],
                    "date": ["type": "string", "description": "Date as YYYY-MM-DD. Use today if not specified."]
                ],
                "required": ["metric", "value"]
            ]
        ],
        [
            "name": "log_medication",
            "description": "Log that a medication was taken. ONLY use when user explicitly says they took a medication.",
            "cache_control": ["type": "ephemeral"],
            "input_schema": [
                "type": "object",
                "properties": [
                    "medicationName": ["type": "string", "description": "Name of the medication"],
                    "date": ["type": "string", "description": "Date as YYYY-MM-DD. Use today if not specified."]
                ],
                "required": ["medicationName"]
            ]
        ]
    ]

    // MARK: - Send Message (with tool use loop)

    func sendMessage(
        conversationHistory: [ChatMessage],
        context: ModelContext
    ) async throws -> String {
        guard hasAPIKey else { throw ClaudeError.noAPIKey }

        isResponding = true
        defer { isResponding = false }

        // Build messages: last 10 for token efficiency
        // conversationHistory already includes the current user message
        // (appended by ChatView before calling sendMessage).
        var messages: [[String: Any]] = []
        for msg in conversationHistory.suffix(10) {
            guard msg.role == .user || msg.role == .assistant else { continue }
            messages.append([
                "role": msg.role.rawValue,
                "content": msg.content
            ])
        }

        // Tool use loop (max 3 rounds — most queries need 1 tool call)
        for _ in 0..<3 {
            let response = try await callAPI(messages: messages)

            // Check stop_reason to determine if we need to handle tool calls
            let isToolUse = response.stopReason == "tool_use"
            let toolUseBlocks = response.content.filter { $0.type == "tool_use" }

            if !isToolUse || toolUseBlocks.isEmpty {
                // Final response — return text
                return response.content
                    .filter { $0.type == "text" }
                    .compactMap(\.text)
                    .joined()
            }

            // Add Claude's response (with tool_use blocks) to messages
            let assistantContent: [[String: Any]] = response.content.map { block in
                if block.type == "tool_use", let id = block.id, let name = block.name, let input = block.input {
                    return ["type": "tool_use", "id": id, "name": name, "input": input]
                } else {
                    return ["type": "text", "text": block.text ?? ""]
                }
            }
            messages.append(["role": "assistant", "content": assistantContent])

            // Execute tools and send results back
            var toolResults: [[String: Any]] = []
            for block in toolUseBlocks {
                guard let toolId = block.id, let toolName = block.name else { continue }
                let input = block.input ?? [:]
                let result = await executeTool(name: toolName, input: input, context: context)
                toolResults.append([
                    "type": "tool_result",
                    "tool_use_id": toolId,
                    "content": result
                ])
            }
            messages.append(["role": "user", "content": toolResults])
        }

        return "I'm having trouble processing this request. Please try again."
    }

    // MARK: - API Call

    private func callAPI(messages: [[String: Any]]) async throws -> ToolResponse {
        guard let url = URL(string: Self.apiURL) else { throw ClaudeError.invalidURL }

        let requestBody: [String: Any] = [
            "model": Self.model,
            "max_tokens": 1024,
            "system": [
                ["type": "text", "text": Self.systemPrompt, "cache_control": ["type": "ephemeral"]]
            ],
            "tools": Self.tools,
            "messages": messages
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("prompt-caching-2024-07-31", forHTTPHeaderField: "anthropic-beta")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        // Log outbound request size
        if let bodySize = request.httpBody?.count {
            let reqLog = ">>> Request body: \(bodySize) bytes, messages: \(messages.count)\n"
            let logURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!.appendingPathComponent("chat-audit.log")
            if let existing = try? String(contentsOf: logURL, encoding: .utf8) {
                try? (existing + reqLog).write(to: logURL, atomically: true, encoding: .utf8)
            } else {
                try? reqLog.write(to: logURL, atomically: true, encoding: .utf8)
            }
        }

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ClaudeError.invalidResponse
        }
        guard httpResponse.statusCode == 200 else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown"
            throw ClaudeError.apiError(statusCode: httpResponse.statusCode, message: errorBody)
        }

        // Diagnostic logging (temporary — remove after audit)
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            var log = "=== API Response ===\n"
            log += "Model: \(json["model"] ?? "?")\n"
            log += "Stop Reason: \(json["stop_reason"] ?? "?")\n"
            if let usage = json["usage"] as? [String: Any] {
                log += "Input Tokens: \(usage["input_tokens"] ?? "?")\n"
                log += "Output Tokens: \(usage["output_tokens"] ?? "?")\n"
                log += "Cache Creation: \(usage["cache_creation_input_tokens"] ?? 0)\n"
                log += "Cache Read: \(usage["cache_read_input_tokens"] ?? 0)\n"
            }
            if let content = json["content"] as? [[String: Any]] {
                for block in content {
                    let type = block["type"] as? String ?? "?"
                    if type == "tool_use" {
                        log += "Tool Call: \(block["name"] ?? "?") -> \(block["input"] ?? [:])\n"
                    } else if type == "text" {
                        let text = (block["text"] as? String) ?? ""
                        log += "Text (\(text.count) chars): \(String(text.prefix(200)))\n"
                    }
                }
            }
            log += "==================\n\n"
            let logURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!.appendingPathComponent("chat-audit.log")
            if let existing = try? String(contentsOf: logURL, encoding: .utf8) {
                try? (existing + log).write(to: logURL, atomically: true, encoding: .utf8)
            } else {
                try? log.write(to: logURL, atomically: true, encoding: .utf8)
            }
        }

        return try JSONDecoder().decode(ToolResponse.self, from: data)
    }

    // MARK: - Tool Execution

    private func executeTool(name: String, input: [String: Any], context: ModelContext) async -> String {
        switch name {
        case "get_vitals":
            return executeGetVitals(input: input, context: context)
        case "get_biomarkers":
            return executeGetBiomarkers(input: input, context: context)
        case "get_medications":
            return executeGetMedications(context: context)
        case "get_conditions":
            return executeGetConditions(context: context)
        case "add_biomarker":
            return executeAddBiomarker(input: input, context: context)
        case "add_measurement":
            return executeAddMeasurement(input: input, context: context)
        case "log_medication":
            return executeLogMedication(input: input, context: context)
        default:
            return "Unknown tool: \(name)"
        }
    }

    // MARK: - Read Tools

    private func executeGetVitals(input: [String: Any], context: ModelContext) -> String {
        let days = min(input["days"] as? Int ?? 7, 90) // Cap at 90 days
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date())!

        let descriptor = FetchDescriptor<Measurement>(
            predicate: #Predicate { $0.timestamp >= cutoff },
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )

        guard let measurements = try? context.fetch(descriptor), !measurements.isEmpty else {
            return "No vitals in the last \(days) days."
        }

        // Filter by metric if specified
        let metricFilter = input["metric"] as? String
        let filtered: [Measurement]
        if let metricFilter, let type = MetricType(rawValue: metricFilter) {
            filtered = measurements.filter { $0.metricType == type }
        } else {
            filtered = Array(measurements)
        }

        if filtered.isEmpty { return "No data for that metric in the last \(days) days." }

        // Group by type, show latest + recent values (capped at 7 per type)
        let grouped = Dictionary(grouping: filtered, by: \.metricType)
        var lines: [String] = []
        for (type, items) in grouped.sorted(by: { $0.key.rawValue < $1.key.rawValue }) {
            let capped = Array(items.prefix(7))
            let latest = capped.first!
            let dateStr = formatDate(latest.timestamp)
            if capped.count > 1 {
                let values = capped.map { $0.displayValue }
                lines.append("\(type.displayName): \(latest.displayValue) \(type.unit) (\(dateStr)) — recent: \(values.joined(separator: ", ")) (\(items.count) total)")
            } else {
                lines.append("\(type.displayName): \(latest.displayValue) \(type.unit) (\(dateStr))")
            }
        }
        return lines.joined(separator: "\n")
    }

    private func executeGetBiomarkers(input: [String: Any], context: ModelContext) -> String {
        let descriptor = FetchDescriptor<Biomarker>(
            sortBy: [SortDescriptor(\.testDate, order: .reverse)]
        )

        guard let biomarkers = try? context.fetch(descriptor), !biomarkers.isEmpty else {
            return "No biomarker data found."
        }

        let markerFilter = input["marker"] as? String
        let systemFilter = input["system"] as? String

        var filtered = biomarkers
        if let markerFilter {
            filtered = filtered.filter { $0.marker.localizedCaseInsensitiveContains(markerFilter) }
        }
        if let systemFilter {
            filtered = filtered.filter { BiomarkerReference.system(for: $0.marker).rawValue == systemFilter }
        }

        if filtered.isEmpty { return "No matching biomarkers found." }

        // Latest per marker — compact format to minimize tokens
        // Show all markers (no cap) since capping triggers multiple follow-up tool calls which costs more
        let grouped = Dictionary(grouping: filtered, by: \.marker)
        var lines: [String] = []
        let sortedMarkers = grouped.sorted { $0.key < $1.key }

        for (marker, items) in sortedMarkers {
            let latest = items.first!
            let status = latest.status.displayName
            let ref: String
            if let min = latest.refMin, let max = latest.refMax {
                ref = " [\(String(format: "%.0f", min))-\(String(format: "%.0f", max))]"
            } else {
                ref = ""
            }
            lines.append("\(marker): \(String(format: "%.1f", latest.value)) \(latest.unit) \(status)\(ref)")
        }

        return lines.joined(separator: "\n")
    }

    private func executeGetMedications(context: ModelContext) -> String {
        let descriptor = FetchDescriptor<Medication>(
            predicate: #Predicate { $0.active }
        )
        guard let meds = try? context.fetch(descriptor), !meds.isEmpty else {
            return "No active medications."
        }
        return meds.map { "\($0.name) \($0.dosage) — \($0.frequency.displayName)" }.joined(separator: "\n")
    }

    private func executeGetConditions(context: ModelContext) -> String {
        let descriptor = FetchDescriptor<Condition>()
        guard let conditions = try? context.fetch(descriptor), !conditions.isEmpty else {
            return "No health conditions recorded."
        }
        return conditions.map { "\($0.name) — \($0.status.displayName)" }.joined(separator: "\n")
    }

    // MARK: - Write Tools

    private func executeAddBiomarker(input: [String: Any], context: ModelContext) -> String {
        guard let marker = input["marker"] as? String,
              let value = input["value"] as? Double,
              let unit = input["unit"] as? String else {
            return "Error: marker, value, and unit are required."
        }

        // Validate value is in a reasonable range
        guard value > 0, value < 100000 else {
            return "Error: value \(value) seems invalid. Please check and try again."
        }

        let dateStr = input["testDate"] as? String
        let testDate = parseDate(dateStr) ?? Date()
        let refMin = input["refMin"] as? Double
        let refMax = input["refMax"] as? Double
        let lab = input["lab"] as? String ?? ""

        // Use known reference ranges if not provided
        let info = BiomarkerReference.info(for: marker)
        let finalRefMin = refMin ?? info?.refMin
        let finalRefMax = refMax ?? info?.refMax

        // Check for duplicate on same day
        let cal = Calendar.current
        let start = cal.startOfDay(for: testDate)
        let end = cal.date(byAdding: .day, value: 1, to: start)!
        let descriptor = FetchDescriptor<Biomarker>(
            predicate: #Predicate { $0.testDate >= start && $0.testDate < end }
        )
        let existing = (try? context.fetch(descriptor)) ?? []
        if existing.contains(where: { $0.marker == marker }) {
            return "Warning: \(marker) already has a value for \(formatDate(testDate)). Not added to avoid duplicate."
        }

        context.insert(Biomarker(
            testDate: testDate,
            marker: marker,
            value: value,
            unit: unit,
            refMin: finalRefMin,
            refMax: finalRefMax,
            lab: lab
        ))
        try? context.save()

        let status = Biomarker(testDate: testDate, marker: marker, value: value, unit: unit, refMin: finalRefMin, refMax: finalRefMax).status
        return "Added: \(marker) = \(String(format: "%.1f", value)) \(unit) (\(status.displayName)) on \(formatDate(testDate))"
    }

    private func executeAddMeasurement(input: [String: Any], context: ModelContext) -> String {
        guard let metricStr = input["metric"] as? String,
              let value = input["value"] as? Double else {
            return "Error: metric and value are required."
        }

        guard let metricType = MetricType(rawValue: metricStr) else {
            return "Error: unknown metric '\(metricStr)'. Valid: weight, heartRate, sleepDuration, steps, activeMinutes, hrv, spo2, calories, bloodPressure"
        }

        // Validate value is reasonable for the metric type
        guard value > 0, value < 100000 else {
            return "Error: value \(value) seems invalid for \(metricType.displayName)."
        }

        let dateStr = input["date"] as? String
        let date = parseDate(dateStr) ?? Date()
        let value2 = input["value2"] as? Double

        let measurement = Measurement(
            timestamp: date,
            metricType: metricType,
            value: value,
            source: .manual
        )
        measurement.value2 = value2
        context.insert(measurement)
        try? context.save()

        return "Added: \(metricType.displayName) = \(measurement.displayValue) \(metricType.unit) on \(formatDate(date))"
    }

    private func executeLogMedication(input: [String: Any], context: ModelContext) -> String {
        guard let name = input["medicationName"] as? String else {
            return "Error: medicationName is required."
        }

        let dateStr = input["date"] as? String
        let date = parseDate(dateStr) ?? Date()

        let descriptor = FetchDescriptor<Medication>(
            predicate: #Predicate { $0.active }
        )
        guard let meds = try? context.fetch(descriptor) else {
            return "Error: could not fetch medications."
        }

        let med = meds.first { $0.name.localizedCaseInsensitiveContains(name) }
        guard let med else {
            let available = meds.map(\.name).joined(separator: ", ")
            return "No active medication matching '\(name)'.\(meds.isEmpty ? "" : " Active: \(available)")"
        }

        context.insert(MedicationLog(date: date, medication: med, taken: true))
        try? context.save()

        return "Logged: \(med.name) taken on \(formatDate(date))"
    }

    // MARK: - Extract Biomarkers from Lab File

    func extractBiomarkers(from fileURL: URL) async throws -> [ExtractedBiomarker] {
        guard hasAPIKey else { throw ClaudeError.noAPIKey }

        isResponding = true
        defer { isResponding = false }

        let accessing = fileURL.startAccessingSecurityScopedResource()
        defer { if accessing { fileURL.stopAccessingSecurityScopedResource() } }

        let contentBlocks: [[String: Any]]
        let isPDF = fileURL.pathExtension.lowercased() == "pdf"

        if isPDF {
            let data = try Data(contentsOf: fileURL)
            let base64 = data.base64EncodedString()
            contentBlocks = [
                [
                    "type": "document",
                    "source": ["type": "base64", "media_type": "application/pdf", "data": base64]
                ],
                ["type": "text", "text": Self.extractionPrompt]
            ]
        } else {
            let text = try String(contentsOf: fileURL, encoding: .utf8)
            contentBlocks = [
                ["type": "text", "text": "Here is a lab report:\n\n\(text)\n\n\(Self.extractionPrompt)"]
            ]
        }

        let requestBody: [String: Any] = [
            "model": Self.model,
            "max_tokens": 4096,
            "messages": [["role": "user", "content": contentBlocks]]
        ]

        guard let url = URL(string: Self.apiURL) else { throw ClaudeError.invalidURL }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 60 // Lab extraction can be slow for large PDFs
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        if isPDF {
            request.setValue("pdfs-2024-09-25", forHTTPHeaderField: "anthropic-beta")
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown"
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw ClaudeError.apiError(statusCode: code, message: errorBody)
        }

        let decoded = try JSONDecoder().decode(ToolResponse.self, from: data)
        let responseText = decoded.content.first?.text ?? ""
        return parseExtractedBiomarkers(responseText)
    }

    private static let extractionPrompt = """
    Extract all numeric biomarker results from this lab report. Return ONLY a JSON array. Each entry:
    - "marker": standardized name (e.g. "Total Cholesterol", "TSH", "Hemoglobin")
    - "value": number
    - "unit": string
    - "refMin": number or null
    - "refMax": number or null
    - "lab": lab name
    - "testDate": "YYYY-MM-DD"

    Skip non-numeric results, urinalysis, physical measurements, and calculated ratios.
    Return ONLY the JSON array starting with [ and ending with ].
    """

    private func parseExtractedBiomarkers(_ text: String) -> [ExtractedBiomarker] {
        guard let startIdx = text.firstIndex(of: "["),
              let endIdx = text.lastIndex(of: "]") else { return [] }
        let jsonString = String(text[startIdx...endIdx])
        guard let jsonData = jsonString.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([ExtractedBiomarker].self, from: jsonData)) ?? []
    }

    // MARK: - Helpers

    private static let displayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d, yyyy"
        return f
    }()

    private static let isoFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private func formatDate(_ date: Date) -> String {
        Self.displayFormatter.string(from: date)
    }

    private func parseDate(_ string: String?) -> Date? {
        guard let string else { return nil }
        return Self.isoFormatter.date(from: string)
    }
}

// MARK: - Models

struct ExtractedBiomarker: Codable, Identifiable {
    var id: String { "\(marker)-\(testDate)" }
    let marker: String
    let value: Double
    let unit: String
    let refMin: Double?
    let refMax: Double?
    let lab: String
    let testDate: String

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    var parsedDate: Date {
        Self.dateFormatter.date(from: testDate) ?? Date()
    }
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

// MARK: - API Response (supports tool use)

struct ToolResponse: Codable {
    let content: [ContentBlock]
    let stopReason: String?

    enum CodingKeys: String, CodingKey {
        case content
        case stopReason = "stop_reason"
    }

    struct ContentBlock: Codable {
        let type: String
        let text: String?
        let id: String?
        let name: String?
        let input: [String: Any]?

        enum CodingKeys: String, CodingKey {
            case type, text, id, name, input
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            type = try container.decode(String.self, forKey: .type)
            text = try container.decodeIfPresent(String.self, forKey: .text)
            id = try container.decodeIfPresent(String.self, forKey: .id)
            name = try container.decodeIfPresent(String.self, forKey: .name)

            if container.contains(.input) {
                let inputData = try container.decode(JSONValue.self, forKey: .input)
                input = inputData.objectValue
            } else {
                input = nil
            }
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(type, forKey: .type)
            try container.encodeIfPresent(text, forKey: .text)
            try container.encodeIfPresent(id, forKey: .id)
            try container.encodeIfPresent(name, forKey: .name)
        }
    }
}

// MARK: - JSON Value Helper (for decoding tool input)

private enum JSONValue: Codable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    var objectValue: [String: Any]? {
        guard case .object(let dict) = self else { return nil }
        return dict.mapValues { $0.anyValue }
    }

    var anyValue: Any {
        switch self {
        case .string(let s): return s
        case .number(let n): return n
        case .bool(let b): return b
        case .object(let d): return d.mapValues { $0.anyValue }
        case .array(let a): return a.map { $0.anyValue }
        case .null: return NSNull()
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let s = try? container.decode(String.self) { self = .string(s); return }
        if let n = try? container.decode(Double.self) { self = .number(n); return }
        if let b = try? container.decode(Bool.self) { self = .bool(b); return }
        if let d = try? container.decode([String: JSONValue].self) { self = .object(d); return }
        if let a = try? container.decode([JSONValue].self) { self = .array(a); return }
        if container.decodeNil() { self = .null; return }
        throw DecodingError.dataCorruptedError(in: container, debugDescription: "Cannot decode JSONValue")
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let s): try container.encode(s)
        case .number(let n): try container.encode(n)
        case .bool(let b): try container.encode(b)
        case .object(let d): try container.encode(d)
        case .array(let a): try container.encode(a)
        case .null: try container.encodeNil()
        }
    }
}
