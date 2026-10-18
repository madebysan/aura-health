import XCTest
@testable import AuraHealth

final class AIProviderTests: XCTestCase {
    func testConsentIsProviderSpecificAndRevocable() throws {
        let suiteName = "AIProviderTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = AIConsentStore(defaults: defaults)

        XCTAssertFalse(store.hasConsent(for: .anthropic))
        XCTAssertFalse(store.hasConsent(for: .openRouter))

        store.grant(for: .anthropic)
        XCTAssertTrue(store.hasConsent(for: .anthropic))
        XCTAssertFalse(store.hasConsent(for: .openRouter))

        store.revoke(for: .anthropic)
        XCTAssertFalse(store.hasConsent(for: .anthropic))
    }

    func testOpenRouterToolCallResponseDecodes() throws {
        let data = Data(#"{"choices":[{"message":{"content":null,"tool_calls":[{"id":"call-1","type":"function","function":{"name":"get_vitals","arguments":"{\"days\":7}"}}]}}]}"#.utf8)

        let response = try JSONDecoder().decode(OpenRouterChatResponse.self, from: data)
        let call = try XCTUnwrap(response.choices.first?.message.toolCalls?.first)

        XCTAssertEqual(call.id, "call-1")
        XCTAssertEqual(call.function.name, "get_vitals")
        XCTAssertEqual(call.function.arguments, #"{"days":7}"#)
    }

    func testOpenRouterRequestUsesBearerAuthAndFunctionTools() throws {
        let request = try AIRequestFactory.openRouterRequest(
            apiKey: "test-key",
            model: "openai/test-model",
            messages: [["role": "user", "content": "Hello"]],
            tools: [["name": "get_vitals", "description": "Read vitals", "input_schema": ["type": "object"]]],
            maxTokens: 1024,
            includeTools: true
        )

        XCTAssertEqual(request.url?.absoluteString, "https://openrouter.ai/api/v1/chat/completions")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-key")

        let bodyData = try XCTUnwrap(request.httpBody)
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: bodyData) as? [String: Any])
        let tools = try XCTUnwrap(body["tools"] as? [[String: Any]])
        XCTAssertEqual(tools.first?["type"] as? String, "function")
        XCTAssertNotNil(tools.first?["function"] as? [String: Any])
        XCTAssertEqual(body["parallel_tool_calls"] as? Bool, true)
    }

    func testCuratedModelsSupportAuraToolsAndAttachments() {
        for provider in AIProvider.allCases where !provider.isOnDevice {
            let models = AIProviderCatalog.models(for: provider)
            XCTAssertFalse(models.isEmpty)
            XCTAssertTrue(models.allSatisfy(\.supportsTools))
            XCTAssertTrue(models.allSatisfy(\.supportsImages))
            XCTAssertTrue(models.allSatisfy(\.supportsPDFs))
        }
    }

    func testOnDeviceModelUsesToolsButReadsTextOnly() {
        let model = AIProviderCatalog.model(id: AIProviderCatalog.defaultModelID(for: .appleOnDevice), provider: .appleOnDevice)
        XCTAssertTrue(model.supportsTools)
        XCTAssertFalse(model.supportsImages)
        XCTAssertFalse(model.supportsPDFs)
        XCTAssertNil(AIKeyStore.value(for: .appleOnDevice))
    }

    func testNewInstallsDefaultToOnDevice() {
        let defaults = UserDefaults.standard
        let saved = defaults.string(forKey: "aiProvider")
        defer { defaults.set(saved, forKey: "aiProvider") }
        defaults.removeObject(forKey: "aiProvider")
        XCTAssertEqual(AIPreferences.provider, .appleOnDevice)
    }

    func testOnDeviceConfirmationsComeFromWhatWasSaved() {
        XCTAssertEqual(OnDeviceAssistant.confirmation(for: "Added: Weight = 80.5 kg on Oct 18, 2026"), "Saved: Weight 80.5 kg on Oct 18, 2026.")
        XCTAssertEqual(OnDeviceAssistant.confirmation(for: "The user did not approve this change. No Aura data was modified."), "Nothing was saved.")
        XCTAssertEqual(OnDeviceAssistant.confirmation(for: "Error: unknown metric 'mood'."), "Nothing was saved. Unknown metric 'mood'.")
        XCTAssertEqual(OnDeviceAssistant.checked("Your weight was logged.", savedSomething: false).prefix(18), "Nothing was saved.")
        XCTAssertEqual(OnDeviceAssistant.checked("Your LDL is 102.", savedSomething: false), "Your LDL is 102.")
    }

    func testOnDeviceRecognizesLoggingRequests() {
        XCTAssertTrue(OnDeviceAssistant.asksToLog("Log my weight at 81 kg"))
        XCTAssertTrue(OnDeviceAssistant.asksToLog("I did my meditation"))
        XCTAssertFalse(OnDeviceAssistant.asksToLog("What biomarkers are out of range?"))
        XCTAssertFalse(OnDeviceAssistant.asksToLog("How has my sleep been this week?"))
        // A cheap first pass: questions with "did" go on to the form reader, which returns none
        XCTAssertTrue(OnDeviceAssistant.asksToLog("How did I sleep this week?"))
    }

    func testOnDevicePromptKeepsRecentTurnsAndTheNewMessage() {
        let history = [
            ChatMessage(role: .user, content: "How did I sleep?"),
            ChatMessage(role: .assistant, content: "About 7 hours most nights."),
            ChatMessage(role: .user, content: "And last night?"),
        ]
        let prompt = OnDeviceAssistant.prompt(from: history)
        XCTAssertTrue(prompt.hasPrefix("Conversation so far:\nUser: How did I sleep?\nAura: About 7 hours most nights."))
        XCTAssertTrue(prompt.hasSuffix("New message: And last night?"))
        XCTAssertEqual(OnDeviceAssistant.prompt(from: [ChatMessage(role: .user, content: "Hi")]), "Hi")
    }

    func testMutatingToolsRequireExplicitApproval() {
        XCTAssertFalse(AIToolPolicy.requiresApproval("get_vitals"))
        XCTAssertFalse(AIToolPolicy.requiresApproval("get_health_summary"))
        XCTAssertTrue(AIToolPolicy.requiresApproval("add_measurement"))
        XCTAssertTrue(AIToolPolicy.requiresApproval("delete_biomarker"))

        let approval = AIToolPolicy.approval(
            for: "delete_biomarker",
            input: ["marker": "LDL Cholesterol"]
        )
        XCTAssertTrue(approval.isDestructive)
        XCTAssertTrue(approval.summary.contains("LDL Cholesterol"))
    }

    @MainActor
    func testHealthChatRefusesToSendWithoutProviderConsent() async throws {
        let defaults = UserDefaults.standard
        let previousProvider = defaults.object(forKey: "aiProvider")
        let previousModel = defaults.object(forKey: "aiModel")
        defer {
            AIKeyStore.removeValue(for: .anthropic)
            if let previousProvider { defaults.set(previousProvider, forKey: "aiProvider") }
            else { defaults.removeObject(forKey: "aiProvider") }
            if let previousModel { defaults.set(previousModel, forKey: "aiModel") }
            else { defaults.removeObject(forKey: "aiModel") }
        }

        defaults.set(AIProvider.anthropic.rawValue, forKey: "aiProvider")
        defaults.set(AIProviderCatalog.defaultModelID(for: .anthropic), forKey: "aiModel")
        AIKeyStore.setValue("test-key-never-sent", for: .anthropic)
        AIConsentStore().revoke(for: .anthropic)

        let container = try AuraStorage.makeContainer(isStoredInMemoryOnly: true)
        let service = AIService()

        do {
            _ = try await service.sendMessage(
                conversationHistory: [ChatMessage(role: .user, content: "Do not send this")],
                context: container.mainContext
            )
            XCTFail("Expected consent to be required before networking")
        } catch ClaudeError.consentRequired {
            // Expected: the request is rejected before transport selection.
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}
