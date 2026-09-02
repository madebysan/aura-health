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
        for provider in AIProvider.allCases {
            let models = AIProviderCatalog.models(for: provider)
            XCTAssertFalse(models.isEmpty)
            XCTAssertTrue(models.allSatisfy(\.supportsTools))
            XCTAssertTrue(models.allSatisfy(\.supportsImages))
            XCTAssertTrue(models.allSatisfy(\.supportsPDFs))
        }
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
