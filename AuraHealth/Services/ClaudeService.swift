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

    private var model: String {
        let stored = UserDefaults.standard.string(forKey: "claudeModel") ?? ClaudeModel.sonnet.rawValue
        return stored
    }

    // MARK: - System Prompt (lean — no data, just behavior rules)

    private static let systemPromptBase = """
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

    NAVIGATION LINKS:
    - When you add or update a measurement or biomarker, end your response with a markdown link so the user can tap to view it.
    - Format: [View in Vitals →](aura://vitals) or [View in Biomarkers →](aura://biomarkers)
    - Use aura://vitals for: heart rate, HRV, blood pressure, weight, sleep, steps, SpO2, temperature, recovery, strain, active minutes.
    - Use aura://biomarkers for: glucose, cholesterol, vitamins, minerals, hormones, and other lab values.
    - Use aura://medications for medication-related updates.
    - Use aura://tracking for habit-related updates.
    - Only include a link when you actually added or updated data. Do NOT add links for read-only queries.
    """

    private var systemPrompt: String {
        let weightUnit = UserDefaults.standard.string(forKey: "weightUnit") ?? "kg"
        let tempUnit = UserDefaults.standard.string(forKey: "temperatureUnit") ?? "celsius"
        let weightLabel = weightUnit == "lbs" ? "lbs (pounds)" : "kg (kilograms)"
        let tempLabel = tempUnit == "fahrenheit" ? "°F (Fahrenheit)" : "°C (Celsius)"
        return Self.systemPromptBase + """

        USER PREFERENCES:
        - Weight unit: \(weightLabel). When the user mentions weight without a unit, assume \(weightUnit). Always pass the correct unit to add_measurement.
        - Temperature unit: \(tempLabel).
        """
    }

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
            "description": "Get lab biomarker results. Use when user asks about blood work, lab results, or specific markers like cholesterol, TSH, ApoB, Apolipoprotein B, glucose, etc. Always call this for any lab/blood test question.",
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
        [
            "name": "get_habits",
            "description": "Get habits list with recent completion status.",
            "input_schema": [
                "type": "object",
                "properties": [:] as [String: Any],
                "required": [] as [String]
            ]
        ],
        [
            "name": "get_diet",
            "description": "Get the current active diet plan with approved and avoided food categories.",
            "input_schema": [
                "type": "object",
                "properties": [:] as [String: Any],
                "required": [] as [String]
            ]
        ],
        [
            "name": "get_health_summary",
            "description": "Get a comprehensive health overview — latest vitals, active conditions, medications, habits, and recent biomarkers. Use when user asks for an overview, summary, or 'how am I doing'.",
            "input_schema": [
                "type": "object",
                "properties": [:] as [String: Any],
                "required": [] as [String]
            ]
        ],
        [
            "name": "import_lab_results",
            "description": "Import biomarkers from an attached lab report file (PDF or image). ONLY use when the user attaches a file and asks to import lab results. The file is already attached to the conversation — just call this tool.",
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
            "description": "Log a vital measurement. ONLY use when user explicitly asks to log/record a measurement. Note: sleepScore, recovery, strain, skinTemp are read-only sensor metrics and cannot be logged manually. For weight: always pass the unit the user specified (lbs or kg). If the user says a number without a unit, use their preferred unit from the system prompt.",
            "input_schema": [
                "type": "object",
                "properties": [
                    "metric": [
                        "type": "string",
                        "enum": ["weight", "heartRate", "sleepDuration", "steps", "activeMinutes", "hrv", "spo2", "calories", "bloodPressure"],
                        "description": "Metric type"
                    ],
                    "value": ["type": "number", "description": "The numeric value in the unit the user specified"],
                    "value2": ["type": "number", "description": "Second value (only for bloodPressure: diastolic)"],
                    "unit": ["type": "string", "description": "Unit for the value. For weight: 'lbs' or 'kg'. For temperature: 'F' or 'C'. If user says pounds/lbs, use 'lbs'. If user says kg/kilograms, use 'kg'."],
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
        ],
        [
            "name": "add_habit",
            "description": "Create a new habit to track. ONLY use when user explicitly asks to add/create a habit.",
            "input_schema": [
                "type": "object",
                "properties": [
                    "name": ["type": "string", "description": "Name of the habit (e.g. 'Reading', 'Meditation', 'Cold Shower')"],
                    "category": [
                        "type": "string",
                        "enum": ["lifestyle", "therapy", "diet", "exercise"],
                        "description": "Category. Default: lifestyle."
                    ],
                    "trackingType": [
                        "type": "string",
                        "enum": ["boolean", "quantity"],
                        "description": "boolean = did/didn't do it, quantity = track a number (e.g. cups of water). Default: boolean."
                    ],
                    "unit": ["type": "string", "description": "Unit for quantity tracking (e.g. 'cups', 'minutes', 'pages'). Only needed if trackingType is quantity."],
                    "gridSection": [
                        "type": "string",
                        "enum": ["morning", "afternoon", "evening", "night"],
                        "description": "When in the day this habit is done. Default: morning."
                    ]
                ],
                "required": ["name"]
            ]
        ],
        [
            "name": "log_habit",
            "description": "Log a habit as completed for today or a given date. ONLY use when user says they did a habit.",
            "input_schema": [
                "type": "object",
                "properties": [
                    "habitName": ["type": "string", "description": "Name of the habit"],
                    "completed": ["type": "boolean", "description": "Whether the habit was completed. Default: true."],
                    "quantity": ["type": "number", "description": "Quantity value (only for quantity-tracked habits)"],
                    "date": ["type": "string", "description": "Date as YYYY-MM-DD. Use today if not specified."]
                ],
                "required": ["habitName"]
            ]
        ],
        [
            "name": "add_condition",
            "description": "Add a health condition. ONLY use when user explicitly asks to add/record a condition.",
            "input_schema": [
                "type": "object",
                "properties": [
                    "name": ["type": "string", "description": "Condition name (e.g. 'Asthma', 'Type 2 Diabetes', 'Anxiety')"],
                    "status": [
                        "type": "string",
                        "enum": ["active", "managed", "resolved"],
                        "description": "Condition status. Default: active."
                    ],
                    "notes": ["type": "string", "description": "Optional notes about the condition"]
                ],
                "required": ["name"]
            ]
        ],
        [
            "name": "add_medication",
            "description": "Add a new medication to track. ONLY use when user explicitly asks to add a medication.",
            "input_schema": [
                "type": "object",
                "properties": [
                    "name": ["type": "string", "description": "Medication name"],
                    "dosage": ["type": "string", "description": "Dosage (e.g. '10mg', '500mg')"],
                    "frequency": [
                        "type": "string",
                        "enum": ["daily", "twiceDaily", "threeTimesDaily", "weekly", "asNeeded"],
                        "description": "How often. Default: daily."
                    ],
                    "type": [
                        "type": "string",
                        "enum": ["rx", "supplement", "otc"],
                        "description": "Medication type. Default: rx."
                    ],
                    "timing": [
                        "type": "string",
                        "enum": ["amFasted", "withFood", "bedtime", "anyTime"],
                        "description": "When to take it. Default: anyTime."
                    ],
                    "condition": ["type": "string", "description": "What condition this is for (optional)"]
                ],
                "required": ["name"]
            ]
        ],
        [
            "name": "deactivate_habit",
            "description": "Deactivate/stop tracking a habit. ONLY use when user asks to stop, remove, or delete a habit.",
            "input_schema": [
                "type": "object",
                "properties": [
                    "habitName": ["type": "string", "description": "Name of the habit to deactivate"]
                ],
                "required": ["habitName"]
            ]
        ],
        [
            "name": "deactivate_medication",
            "description": "Deactivate/stop a medication. ONLY use when user says they stopped taking a medication.",
            "input_schema": [
                "type": "object",
                "properties": [
                    "medicationName": ["type": "string", "description": "Name of the medication to deactivate"]
                ],
                "required": ["medicationName"]
            ]
        ],
        [
            "name": "update_condition",
            "description": "Update a condition's status. Use when user says a condition is now managed, resolved, etc.",
            "input_schema": [
                "type": "object",
                "properties": [
                    "name": ["type": "string", "description": "Condition name"],
                    "status": [
                        "type": "string",
                        "enum": ["active", "managed", "resolved"],
                        "description": "New status"
                    ]
                ],
                "required": ["name", "status"]
            ]
        ],
        [
            "name": "delete_measurement",
            "description": "Delete a vital measurement entry. ONLY use when user explicitly asks to delete/remove a specific measurement. Always confirm what will be deleted before calling. If multiple entries match, list them and ask which one to delete.",
            "input_schema": [
                "type": "object",
                "properties": [
                    "metric": [
                        "type": "string",
                        "enum": ["weight", "heartRate", "sleepDuration", "steps", "activeMinutes", "hrv", "spo2", "calories", "bloodPressure"],
                        "description": "Metric type to delete"
                    ],
                    "date": ["type": "string", "description": "Date of the entry as YYYY-MM-DD. Required to avoid deleting the wrong entry."],
                    "value": ["type": "number", "description": "The value to match (optional, for disambiguation when multiple entries exist on the same date)"]
                ],
                "required": ["metric", "date"]
            ]
        ],
        [
            "name": "delete_biomarker",
            "description": "Delete a biomarker/lab result entry. ONLY use when user explicitly asks to delete/remove a specific biomarker. Always confirm what will be deleted before calling.",
            "input_schema": [
                "type": "object",
                "properties": [
                    "marker": ["type": "string", "description": "Marker name (e.g. 'Total Cholesterol', 'TSH')"],
                    "date": ["type": "string", "description": "Test date as YYYY-MM-DD. Required to avoid deleting the wrong entry."],
                    "value": ["type": "number", "description": "The value to match (optional, for disambiguation)"]
                ],
                "required": ["marker", "date"]
            ]
        ],
        [
            "name": "navigate",
            "description": "Navigate to a specific section of the app. Use when user says 'show me', 'go to', 'open' a section.",
            "input_schema": [
                "type": "object",
                "properties": [
                    "section": [
                        "type": "string",
                        "enum": ["today", "vitals", "correlations", "conditions", "medications", "biomarkers", "diet", "exercise", "vault", "settings"],
                        "description": "App section to navigate to"
                    ]
                ],
                "required": ["section"]
            ]
        ]
    ]

    // MARK: - Send Message (with tool use loop)

    /// Attached file URL for the current message (set by the chat UI before calling sendMessage)
    var pendingFileURL: URL?

    func sendMessage(
        conversationHistory: [ChatMessage],
        context: ModelContext
    ) async throws -> String {
        guard hasAPIKey else { throw ClaudeError.noAPIKey }

        hasFileAttachment = false
        defer { hasFileAttachment = false }

        // Build messages: last 10 for token efficiency
        // conversationHistory already includes the current user message
        // (appended by ChatView before calling sendMessage).
        var messages: [[String: Any]] = []
        let recentMessages = Array(conversationHistory.suffix(10))
        for (index, msg) in recentMessages.enumerated() {
            guard msg.role == .user || msg.role == .assistant else { continue }

            // Attach file content to the last user message if we have a pending file
            let isLastMessage = index == recentMessages.count - 1
            if isLastMessage && msg.role == .user, let fileURL = pendingFileURL {
                let contentBlocks = buildFileContentBlocks(text: msg.content, fileURL: fileURL)
                messages.append(["role": "user", "content": contentBlocks])
                pendingFileURL = nil
            } else {
                messages.append([
                    "role": msg.role.rawValue,
                    "content": msg.content
                ])
            }
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

    // MARK: - File Content Helpers

    private var hasFileAttachment = false

    private func buildFileContentBlocks(text: String, fileURL: URL) -> [[String: Any]] {
        let accessing = fileURL.startAccessingSecurityScopedResource()
        defer { if accessing { fileURL.stopAccessingSecurityScopedResource() } }

        let ext = fileURL.pathExtension.lowercased()
        var blocks: [[String: Any]] = []

        if ext == "pdf" {
            if let data = try? Data(contentsOf: fileURL) {
                blocks.append([
                    "type": "document",
                    "source": ["type": "base64", "media_type": "application/pdf", "data": data.base64EncodedString()]
                ])
                hasFileAttachment = true
            }
        } else if ["jpg", "jpeg", "png", "gif", "webp"].contains(ext) {
            if let data = try? Data(contentsOf: fileURL) {
                let mediaType = ext == "png" ? "image/png" : ext == "gif" ? "image/gif" : ext == "webp" ? "image/webp" : "image/jpeg"
                blocks.append([
                    "type": "image",
                    "source": ["type": "base64", "media_type": mediaType, "data": data.base64EncodedString()]
                ])
                hasFileAttachment = true
            }
        } else {
            // Plain text file
            if let content = try? String(contentsOf: fileURL, encoding: .utf8) {
                blocks.append(["type": "text", "text": "Attached file (\(fileURL.lastPathComponent)):\n\n\(content)"])
            }
        }

        blocks.append(["type": "text", "text": text])
        return blocks
    }

    // MARK: - API Call

    private func callAPI(messages: [[String: Any]]) async throws -> ToolResponse {
        guard let url = URL(string: Self.apiURL) else { throw ClaudeError.invalidURL }

        let maxTokens = hasFileAttachment ? 4096 : 1024

        let requestBody: [String: Any] = [
            "model": model,
            "max_tokens": maxTokens,
            "system": [
                ["type": "text", "text": systemPrompt, "cache_control": ["type": "ephemeral"]]
            ],
            "tools": Self.tools,
            "messages": messages
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = hasFileAttachment ? 60 : 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        let beta = hasFileAttachment ? "prompt-caching-2024-07-31,pdfs-2024-09-25" : "prompt-caching-2024-07-31"
        request.setValue(beta, forHTTPHeaderField: "anthropic-beta")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ClaudeError.invalidResponse
        }
        guard httpResponse.statusCode == 200 else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown"
            throw ClaudeError.apiError(statusCode: httpResponse.statusCode, message: errorBody)
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
        case "get_habits":
            return executeGetHabits(context: context)
        case "add_habit":
            return executeAddHabit(input: input, context: context)
        case "log_habit":
            return executeLogHabit(input: input, context: context)
        case "add_condition":
            return executeAddCondition(input: input, context: context)
        case "add_medication":
            return executeAddMedication(input: input, context: context)
        case "add_biomarker":
            return executeAddBiomarker(input: input, context: context)
        case "add_measurement":
            return executeAddMeasurement(input: input, context: context)
        case "log_medication":
            return executeLogMedication(input: input, context: context)
        case "get_diet":
            return executeGetDiet(context: context)
        case "get_health_summary":
            return await executeGetHealthSummary(context: context)
        case "import_lab_results":
            return await executeImportLabResults(context: context)
        case "deactivate_habit":
            return executeDeactivateHabit(input: input, context: context)
        case "deactivate_medication":
            return executeDeactivateMedication(input: input, context: context)
        case "update_condition":
            return executeUpdateCondition(input: input, context: context)
        case "delete_measurement":
            return executeDeleteMeasurement(input: input, context: context)
        case "delete_biomarker":
            return executeDeleteBiomarker(input: input, context: context)
        case "navigate":
            return executeNavigate(input: input)
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
            let canonical = BiomarkerReference.canonicalName(for: markerFilter)
            filtered = filtered.filter {
                $0.marker.localizedCaseInsensitiveContains(markerFilter)
                || $0.marker.localizedCaseInsensitiveContains(canonical)
            }
        }
        if let systemFilter {
            filtered = filtered.filter { BiomarkerReference.system(for: $0.marker).rawValue == systemFilter }
        }

        if filtered.isEmpty {
            let allMarkers = Array(Set(biomarkers.map(\.marker))).sorted().joined(separator: ", ")
            return "No biomarker named '\(markerFilter ?? "")' found. Markers on record: \(allMarkers)"
        }

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

    private func executeGetHabits(context: ModelContext) -> String {
        let descriptor = FetchDescriptor<Habit>(
            predicate: #Predicate { $0.active }
        )
        guard let habits = try? context.fetch(descriptor), !habits.isEmpty else {
            return "No active habits."
        }

        let today = Calendar.current.startOfDay(for: Date())
        return habits.map { habit in
            let todayLog = (habit.logs ?? []).first { Calendar.current.isDate($0.date, inSameDayAs: today) }
            let status = todayLog?.done == true ? "done" : "pending"
            let section = habit.gridSection.displayName.lowercased()
            if habit.trackingType == .quantity, let qty = todayLog?.quantity, qty > 0 {
                return "\(habit.name) (\(section), \(habit.category.displayName)) — \(Int(qty)) \(habit.unit) today"
            }
            return "\(habit.name) (\(section), \(habit.category.displayName)) — \(status)"
        }.joined(separator: "\n")
    }

    // MARK: - Write Tools

    private func executeAddHabit(input: [String: Any], context: ModelContext) -> String {
        guard let name = input["name"] as? String, !name.isEmpty else {
            return "Error: habit name is required."
        }

        // Check for duplicate
        let descriptor = FetchDescriptor<Habit>(
            predicate: #Predicate { $0.active }
        )
        let existing = (try? context.fetch(descriptor)) ?? []
        if existing.contains(where: { $0.name.localizedCaseInsensitiveContains(name) }) {
            return "A habit named '\(name)' already exists."
        }

        let category = (input["category"] as? String).flatMap { HabitCategory(rawValue: $0) } ?? .lifestyle
        let trackingType = (input["trackingType"] as? String).flatMap { TrackingType(rawValue: $0) } ?? .boolean
        let unit = input["unit"] as? String ?? ""
        let gridSection = (input["gridSection"] as? String).flatMap { GridSection(rawValue: $0) } ?? .morning

        let habit = Habit(
            name: name,
            category: category,
            trackingType: trackingType,
            unit: unit,
            gridSection: gridSection
        )
        context.insert(habit)
        try? context.save()

        return "Created habit: \(name) (\(category.displayName), \(gridSection.displayName))\(trackingType == .quantity ? " — tracking \(unit)" : "")"
    }

    private func executeLogHabit(input: [String: Any], context: ModelContext) -> String {
        guard let name = input["habitName"] as? String else {
            return "Error: habitName is required."
        }

        let dateStr = input["date"] as? String
        let date = parseDate(dateStr) ?? Date()
        let completed = input["completed"] as? Bool ?? true
        let quantity = input["quantity"] as? Double

        let descriptor = FetchDescriptor<Habit>(
            predicate: #Predicate { $0.active }
        )
        guard let habits = try? context.fetch(descriptor) else {
            return "Error: could not fetch habits."
        }

        let habit = habits.first { $0.name.localizedCaseInsensitiveContains(name) }
        guard let habit else {
            let available = habits.map(\.name).joined(separator: ", ")
            return "No active habit matching '\(name)'.\(habits.isEmpty ? "" : " Active: \(available)")"
        }

        // Check for existing log on this date
        let existingLog = (habit.logs ?? []).first { Calendar.current.isDate($0.date, inSameDayAs: date) }
        if let existingLog {
            existingLog.done = completed
            if let quantity { existingLog.quantity = quantity }
        } else {
            let log = HabitLog(date: date, habit: habit, done: completed)
            if let quantity { log.quantity = quantity }
            context.insert(log)
        }
        try? context.save()

        if let quantity, habit.trackingType == .quantity {
            return "Logged: \(habit.name) — \(Int(quantity)) \(habit.unit) on \(formatDate(date))"
        }
        return "Logged: \(habit.name) — \(completed ? "completed" : "skipped") on \(formatDate(date))"
    }

    private func executeAddCondition(input: [String: Any], context: ModelContext) -> String {
        guard let name = input["name"] as? String, !name.isEmpty else {
            return "Error: condition name is required."
        }

        // Check for duplicate
        let descriptor = FetchDescriptor<Condition>()
        let existing = (try? context.fetch(descriptor)) ?? []
        if existing.contains(where: { $0.name.localizedCaseInsensitiveContains(name) }) {
            return "Condition '\(name)' already exists."
        }

        let status = (input["status"] as? String).flatMap { ConditionStatus(rawValue: $0) } ?? .active
        let notes = input["notes"] as? String ?? ""

        context.insert(Condition(name: name, status: status, notes: notes))
        try? context.save()

        return "Added condition: \(name) (\(status.displayName))"
    }

    private func executeAddMedication(input: [String: Any], context: ModelContext) -> String {
        guard let name = input["name"] as? String, !name.isEmpty else {
            return "Error: medication name is required."
        }

        // Check for duplicate
        let descriptor = FetchDescriptor<Medication>(
            predicate: #Predicate { $0.active }
        )
        let existing = (try? context.fetch(descriptor)) ?? []
        if existing.contains(where: { $0.name.localizedCaseInsensitiveContains(name) }) {
            return "Medication '\(name)' already exists."
        }

        let dosage = input["dosage"] as? String ?? ""
        let frequency = (input["frequency"] as? String).flatMap { MedicationFrequency(rawValue: $0) } ?? .daily
        let type = (input["type"] as? String).flatMap { MedicationType(rawValue: $0) } ?? .rx
        let timing = (input["timing"] as? String).flatMap { MedicationTiming(rawValue: $0) } ?? .anyTime
        let condition = input["condition"] as? String ?? ""

        context.insert(Medication(
            name: name,
            dosage: dosage,
            frequency: frequency,
            condition: condition,
            type: type,
            timing: timing
        ))
        try? context.save()

        return "Added medication: \(name)\(dosage.isEmpty ? "" : " \(dosage)") — \(frequency.displayName), \(timing.displayName)"
    }

    private func executeAddBiomarker(input: [String: Any], context: ModelContext) -> String {
        guard let rawMarker = input["marker"] as? String,
              let value = input["value"] as? Double,
              let unit = input["unit"] as? String else {
            return "Error: marker, value, and unit are required."
        }

        // Normalize aliases (e.g. "ApoB" → "Apolipoprotein B")
        let marker = BiomarkerReference.canonicalName(for: rawMarker)

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
        let inputUnit = input["unit"] as? String

        // Convert weight to kg for storage (app stores weight internally in kg)
        var storageValue = value
        var displayUnit = metricType.unit
        if metricType == .weight, let inputUnit {
            if inputUnit.lowercased() == "lbs" {
                storageValue = value / 2.20462 // lbs → kg
                displayUnit = "lbs"
            } else {
                displayUnit = "kg"
            }
        }

        let measurement = Measurement(
            timestamp: date,
            metricType: metricType,
            value: storageValue,
            source: .manual
        )
        measurement.value2 = value2
        context.insert(measurement)
        try? context.save()

        // Report back in the unit the user used, not the storage unit
        let reportValue = metricType == .weight && displayUnit == "lbs" ? value : storageValue
        let reportDisplay = reportValue == reportValue.rounded() ? "\(Int(reportValue))" : String(format: "%.1f", reportValue)
        return "Added: \(metricType.displayName) = \(reportDisplay) \(displayUnit) on \(formatDate(date))"
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

    // MARK: - Read Tools (continued)

    private func executeGetDiet(context: ModelContext) -> String {
        let descriptor = FetchDescriptor<DietPlan>(
            predicate: #Predicate { $0.active }
        )
        guard let plans = try? context.fetch(descriptor), !plans.isEmpty else {
            return "No active diet plan."
        }
        return plans.map { plan in
            var parts = ["\(plan.name) (\(plan.dietType.isEmpty ? "custom" : plan.dietType))"]
            if !plan.allowedFoods.isEmpty { parts.append("Allowed: \(plan.allowedFoods.joined(separator: ", "))") }
            if !plan.avoidFoods.isEmpty { parts.append("Avoid: \(plan.avoidFoods.joined(separator: ", "))") }
            if !plan.notes.isEmpty { parts.append("Notes: \(plan.notes)") }
            return parts.joined(separator: "\n  ")
        }.joined(separator: "\n\n")
    }

    private func executeGetHealthSummary(context: ModelContext) async -> String {
        var sections: [String] = []

        // Latest vitals (last 7 days)
        let vitals = executeGetVitals(input: ["days": 7], context: context)
        if !vitals.contains("No vitals") { sections.append("VITALS (7d):\n\(vitals)") }

        // Active conditions
        let conditions = executeGetConditions(context: context)
        if !conditions.contains("No health") { sections.append("CONDITIONS:\n\(conditions)") }

        // Active medications
        let meds = executeGetMedications(context: context)
        if !meds.contains("No active") { sections.append("MEDICATIONS:\n\(meds)") }

        // Active habits
        let habits = executeGetHabits(context: context)
        if !habits.contains("No active") { sections.append("HABITS:\n\(habits)") }

        // Active diet
        let diet = executeGetDiet(context: context)
        if !diet.contains("No active") { sections.append("DIET:\n\(diet)") }

        // Recent biomarkers (latest per marker)
        let biomarkers = executeGetBiomarkers(input: [:], context: context)
        if !biomarkers.contains("No biomarker") { sections.append("BIOMARKERS:\n\(biomarkers)") }

        if sections.isEmpty { return "No health data recorded yet." }
        return sections.joined(separator: "\n\n")
    }

    private func executeImportLabResults(context: ModelContext) async -> String {
        guard let fileURL = pendingFileURL else {
            return "No file attached. Please attach a lab report PDF or image and try again."
        }

        do {
            let extracted = try await extractBiomarkers(from: fileURL)
            if extracted.isEmpty {
                return "Could not extract any biomarker values from the file."
            }

            var added = 0
            var skipped = 0
            for marker in extracted {
                // Check for duplicate on same day
                let testDate = marker.parsedDate
                let cal = Calendar.current
                let start = cal.startOfDay(for: testDate)
                let end = cal.date(byAdding: .day, value: 1, to: start)!
                let descriptor = FetchDescriptor<Biomarker>(
                    predicate: #Predicate { $0.testDate >= start && $0.testDate < end }
                )
                let existing = (try? context.fetch(descriptor)) ?? []
                if existing.contains(where: { $0.marker == marker.marker }) {
                    skipped += 1
                    continue
                }

                let info = BiomarkerReference.info(for: marker.marker)
                context.insert(Biomarker(
                    testDate: testDate,
                    marker: marker.marker,
                    value: marker.value,
                    unit: marker.unit,
                    refMin: marker.refMin ?? info?.refMin,
                    refMax: marker.refMax ?? info?.refMax,
                    lab: marker.lab
                ))
                added += 1
            }
            try? context.save()

            var result = "Imported \(added) biomarker\(added == 1 ? "" : "s") from lab report."
            if skipped > 0 { result += " Skipped \(skipped) duplicate\(skipped == 1 ? "" : "s")." }
            return result
        } catch {
            return "Error processing lab file: \(error.localizedDescription)"
        }
    }

    // MARK: - Write Tools (continued)

    private func executeDeactivateHabit(input: [String: Any], context: ModelContext) -> String {
        guard let name = input["habitName"] as? String else {
            return "Error: habitName is required."
        }

        let descriptor = FetchDescriptor<Habit>(
            predicate: #Predicate { $0.active }
        )
        guard let habits = try? context.fetch(descriptor) else {
            return "Error: could not fetch habits."
        }

        guard let habit = habits.first(where: { $0.name.localizedCaseInsensitiveContains(name) }) else {
            let available = habits.map(\.name).joined(separator: ", ")
            return "No active habit matching '\(name)'.\(habits.isEmpty ? "" : " Active: \(available)")"
        }

        habit.active = false
        try? context.save()
        return "Deactivated habit: \(habit.name)"
    }

    private func executeDeactivateMedication(input: [String: Any], context: ModelContext) -> String {
        guard let name = input["medicationName"] as? String else {
            return "Error: medicationName is required."
        }

        let descriptor = FetchDescriptor<Medication>(
            predicate: #Predicate { $0.active }
        )
        guard let meds = try? context.fetch(descriptor) else {
            return "Error: could not fetch medications."
        }

        guard let med = meds.first(where: { $0.name.localizedCaseInsensitiveContains(name) }) else {
            let available = meds.map(\.name).joined(separator: ", ")
            return "No active medication matching '\(name)'.\(meds.isEmpty ? "" : " Active: \(available)")"
        }

        med.active = false
        try? context.save()
        return "Deactivated medication: \(med.name)"
    }

    private func executeUpdateCondition(input: [String: Any], context: ModelContext) -> String {
        guard let name = input["name"] as? String,
              let statusStr = input["status"] as? String,
              let status = ConditionStatus(rawValue: statusStr) else {
            return "Error: name and valid status (active, managed, resolved) are required."
        }

        let descriptor = FetchDescriptor<Condition>()
        guard let conditions = try? context.fetch(descriptor) else {
            return "Error: could not fetch conditions."
        }

        guard let condition = conditions.first(where: { $0.name.localizedCaseInsensitiveContains(name) }) else {
            let available = conditions.map(\.name).joined(separator: ", ")
            return "No condition matching '\(name)'.\(conditions.isEmpty ? "" : " Existing: \(available)")"
        }

        let oldStatus = condition.status.displayName
        condition.status = status
        try? context.save()
        return "Updated \(condition.name): \(oldStatus) → \(status.displayName)"
    }

    private func executeDeleteMeasurement(input: [String: Any], context: ModelContext) -> String {
        guard let metricStr = input["metric"] as? String,
              let dateStr = input["date"] as? String else {
            return "Error: metric and date are required."
        }

        guard let metricType = MetricType(rawValue: metricStr) else {
            return "Error: unknown metric '\(metricStr)'."
        }

        guard let targetDate = parseDate(dateStr) else {
            return "Error: invalid date format. Use YYYY-MM-DD."
        }

        let cal = Calendar.current
        let descriptor = FetchDescriptor<Measurement>(
            predicate: #Predicate { $0.metricType == metricType },
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )

        guard let measurements = try? context.fetch(descriptor) else {
            return "Error: could not fetch measurements."
        }

        let matches = measurements.filter { cal.isDate($0.timestamp, inSameDayAs: targetDate) }

        if matches.isEmpty {
            return "No \(metricType.displayName) entry found on \(formatDate(targetDate))."
        }

        // If a value was provided, narrow down further
        let valueFilter = input["value"] as? Double
        let toDelete: [Measurement]
        if let valueFilter {
            toDelete = matches.filter { abs($0.value - valueFilter) < 0.01 }
            if toDelete.isEmpty {
                let existing = matches.map { "\($0.displayValue) \(metricType.unit)" }.joined(separator: ", ")
                return "No \(metricType.displayName) entry with value \(valueFilter) on \(formatDate(targetDate)). Found: \(existing)"
            }
        } else if matches.count > 1 {
            let list = matches.map { "\($0.displayValue) \(metricType.unit) (\($0.timestamp.formatted(.dateTime.hour().minute())))" }.joined(separator: ", ")
            return "Multiple entries on \(formatDate(targetDate)): \(list). Specify the value to delete the right one."
        } else {
            toDelete = matches
        }

        for m in toDelete {
            context.delete(m)
        }
        try? context.save()

        let deleted = toDelete.map { "\($0.displayValue) \(metricType.unit)" }.joined(separator: ", ")
        return "Deleted \(metricType.displayName): \(deleted) from \(formatDate(targetDate))."
    }

    private func executeDeleteBiomarker(input: [String: Any], context: ModelContext) -> String {
        guard let markerName = input["marker"] as? String,
              let dateStr = input["date"] as? String else {
            return "Error: marker and date are required."
        }

        guard let targetDate = parseDate(dateStr) else {
            return "Error: invalid date format. Use YYYY-MM-DD."
        }

        let cal = Calendar.current
        let descriptor = FetchDescriptor<Biomarker>(
            sortBy: [SortDescriptor(\.testDate, order: .reverse)]
        )

        guard let biomarkers = try? context.fetch(descriptor) else {
            return "Error: could not fetch biomarkers."
        }

        let matches = biomarkers.filter {
            $0.marker.localizedCaseInsensitiveContains(markerName) &&
            cal.isDate($0.testDate, inSameDayAs: targetDate)
        }

        if matches.isEmpty {
            return "No biomarker matching '\(markerName)' found on \(formatDate(targetDate))."
        }

        // If a value was provided, narrow down
        let valueFilter = input["value"] as? Double
        let toDelete: [Biomarker]
        if let valueFilter {
            toDelete = matches.filter { abs($0.value - valueFilter) < 0.01 }
            if toDelete.isEmpty {
                let existing = matches.map { "\($0.marker): \($0.value) \($0.unit)" }.joined(separator: ", ")
                return "No match with value \(valueFilter). Found: \(existing)"
            }
        } else {
            toDelete = matches
        }

        for b in toDelete {
            context.delete(b)
        }
        try? context.save()

        let deleted = toDelete.map { "\($0.marker): \($0.value) \($0.unit)" }.joined(separator: ", ")
        return "Deleted: \(deleted) from \(formatDate(targetDate))."
    }

    private func executeNavigate(input: [String: Any]) -> String {
        guard let sectionStr = input["section"] as? String,
              let section = AppSection(rawValue: sectionStr) else {
            return "Error: valid section name is required."
        }

        NotificationCenter.default.post(name: .navigateTo, object: section)
        return "Navigated to \(section.label)."
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
            "model": model,
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
