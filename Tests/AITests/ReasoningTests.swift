import XCTest
@testable import AI
import AITesting

final class ReasoningTests: XCTestCase {

    private func request(
        _ reasoning: ReasoningEffort,
        maxOutputTokens: Int = 1024,
        providerOptions: JSONValue? = nil
    ) -> LanguageModelRequest {
        LanguageModelRequest(
            messages: [.user("hi")],
            maxOutputTokens: maxOutputTokens,
            reasoning: reasoning,
            providerOptions: providerOptions
        )
    }

    func testReasoningRidesTheRequestThroughStreamText() async throws {
        let model = MockLanguageModel(text: "ok")
        _ = try await generateText(model: model, prompt: "hi", reasoning: .high)
        XCTAssertEqual(model.requests[0].reasoning, .high)

        _ = try await generateText(model: model, prompt: "hi")
        XCTAssertEqual(model.requests[1].reasoning, .providerDefault)
    }

    func testBudgetMappingMatchesProviderUtils() {
        XCTAssertEqual(
            ReasoningEffort.medium.budget(maxOutputTokens: 64000, maxBudget: 64000), 19200
        )
        XCTAssertEqual(
            ReasoningEffort.xhigh.budget(maxOutputTokens: 65536, maxBudget: 24576, minBudget: 0),
            24576
        )
        XCTAssertEqual(
            ReasoningEffort.minimal.budget(maxOutputTokens: 4096, maxBudget: 4096), 1024
        )
        XCTAssertNil(ReasoningEffort.none.budget(maxOutputTokens: 64000, maxBudget: 64000))
        XCTAssertNil(
            ReasoningEffort.providerDefault.budget(maxOutputTokens: 64000, maxBudget: 64000)
        )
    }

    private func chatBody(
        _ reasoning: ReasoningEffort,
        style: OpenAIChatModel.ReasoningWireStyle,
        modelID: String = "test-model",
        providerOptions: JSONValue? = nil
    ) -> [String: JSONValue] {
        OpenAIChatModel.requestBody(
            for: request(reasoning, providerOptions: providerOptions),
            modelID: modelID,
            reasoningStyle: style
        ).objectValue ?? [:]
    }

    func testOpenAIChatSendsEffortVerbatimIncludingNone() {
        XCTAssertEqual(
            chatBody(.xhigh, style: .openAI)["reasoning_effort"]?.stringValue, "xhigh"
        )
        XCTAssertEqual(
            chatBody(.none, style: .openAI)["reasoning_effort"]?.stringValue, "none"
        )
        XCTAssertNil(chatBody(.providerDefault, style: .openAI)["reasoning_effort"])
    }

    func testCompatibleOmitsNoneAndPassesTheRest() {
        XCTAssertEqual(
            chatBody(.xhigh, style: .compatible)["reasoning_effort"]?.stringValue, "xhigh"
        )
        XCTAssertNil(chatBody(.none, style: .compatible)["reasoning_effort"])
    }

    func testFireworksCoercesToItsThreeLevels() {
        XCTAssertEqual(
            chatBody(.minimal, style: .fireworks)["reasoning_effort"]?.stringValue, "low"
        )
        XCTAssertEqual(
            chatBody(.xhigh, style: .fireworks)["reasoning_effort"]?.stringValue, "high"
        )
        XCTAssertEqual(
            chatBody(.medium, style: .fireworks)["reasoning_effort"]?.stringValue, "medium"
        )
    }

    func testGroqMapsAndOmitsNone() {
        XCTAssertEqual(
            chatBody(.xhigh, style: .groq)["reasoning_effort"]?.stringValue, "high"
        )
        XCTAssertEqual(
            chatBody(.minimal, style: .groq)["reasoning_effort"]?.stringValue, "low"
        )
        XCTAssertNil(chatBody(.none, style: .groq)["reasoning_effort"])
    }

    func testXaiChatSendsNoneAndSkipsFixedReasoningModels() {
        XCTAssertEqual(
            chatBody(.none, style: .xaiChat, modelID: "grok-4")["reasoning_effort"]?.stringValue,
            "none"
        )
        XCTAssertEqual(
            chatBody(.minimal, style: .xaiChat, modelID: "grok-4")["reasoning_effort"]?.stringValue,
            "low"
        )
        XCTAssertNil(
            chatBody(.high, style: .xaiChat, modelID: "grok-4.20-reasoning")["reasoning_effort"]
        )
        XCTAssertNil(
            chatBody(.high, style: .xaiChat, modelID: "grok-4.20-2004-non-reasoning")["reasoning_effort"]
        )
    }

    func testDeepSeekSendsThinkingPlusEffort() {
        let high = chatBody(.high, style: .deepseek)
        XCTAssertEqual(high["thinking"]?["type"]?.stringValue, "enabled")
        XCTAssertEqual(high["reasoning_effort"]?.stringValue, "high")

        XCTAssertEqual(
            chatBody(.xhigh, style: .deepseek)["reasoning_effort"]?.stringValue, "max"
        )

        let off = chatBody(.none, style: .deepseek)
        XCTAssertEqual(off["thinking"]?["type"]?.stringValue, "disabled")
        XCTAssertNil(off["reasoning_effort"])
    }

    func testMistralOnlyOnItsReasoningModels() {
        XCTAssertEqual(
            chatBody(.medium, style: .mistral, modelID: "mistral-small-latest")["reasoning_effort"]?.stringValue,
            "high"
        )
        XCTAssertEqual(
            chatBody(.none, style: .mistral, modelID: "mistral-medium-3.5")["reasoning_effort"]?.stringValue,
            "none"
        )
        XCTAssertNil(
            chatBody(.high, style: .mistral, modelID: "mistral-large-latest")["reasoning_effort"]
        )
    }

    func testPerplexityIgnoresReasoning() {
        XCTAssertNil(chatBody(.high, style: .unsupported)["reasoning_effort"])
    }

    func testProviderOptionsBeatTheUnifiedSetting() {
        let body = chatBody(
            .high, style: .openAI,
            providerOptions: .object(["reasoning_effort": .string("low")])
        )
        XCTAssertEqual(body["reasoning_effort"]?.stringValue, "low")
    }

    func testEngineDerivesStyleFromProviderName() {
        XCTAssertEqual(OpenAIChatModel.ReasoningWireStyle.forProvider("openai"), .openAI)
        XCTAssertEqual(OpenAIChatModel.ReasoningWireStyle.forProvider("groq"), .groq)
        XCTAssertEqual(OpenAIChatModel.ReasoningWireStyle.forProvider("deepseek"), .deepseek)
        XCTAssertEqual(OpenAIChatModel.ReasoningWireStyle.forProvider("mistral"), .mistral)
        XCTAssertEqual(OpenAIChatModel.ReasoningWireStyle.forProvider("perplexity"), .unsupported)
        XCTAssertEqual(OpenAIChatModel.ReasoningWireStyle.forProvider("fireworks"), .fireworks)
        XCTAssertEqual(OpenAIChatModel.ReasoningWireStyle.forProvider("togetherai"), .compatible)
    }

    func testResponsesSendsEffortAndDetailedSummary() {
        let body = OpenAIModel.responsesBody(
            for: request(.high), modelID: "gpt-5.6-luna"
        ).objectValue ?? [:]
        XCTAssertEqual(body["reasoning"]?["effort"]?.stringValue, "high")
        XCTAssertEqual(body["reasoning"]?["summary"]?.stringValue, "detailed")
    }

    func testResponsesNoneSkipsSummaryAndKeepsSampling() {
        let body = OpenAIModel.responsesBody(
            for: LanguageModelRequest(
                messages: [.user("hi")], temperature: 0.5, reasoning: ReasoningEffort.none
            ),
            modelID: "gpt-5.6-luna"
        ).objectValue ?? [:]
        XCTAssertEqual(body["reasoning"]?["effort"]?.stringValue, "none")
        XCTAssertNil(body["reasoning"]?["summary"])
        XCTAssertEqual(body["temperature"]?.doubleValue, 0.5)
    }

    func testResponsesIgnoresReasoningOnNonReasoningModels() {
        let body = OpenAIModel.responsesBody(
            for: request(.high), modelID: "gpt-4o"
        ).objectValue ?? [:]
        XCTAssertNil(body["reasoning"])
    }

    func testResponsesProviderOptionsWin() {
        let body = OpenAIModel.responsesBody(
            for: request(
                .high,
                providerOptions: .object([
                    "reasoning": .object(["effort": .string("low")])
                ])
            ),
            modelID: "gpt-5.6-luna"
        ).objectValue ?? [:]
        XCTAssertEqual(body["reasoning"]?["effort"]?.stringValue, "low")
        XCTAssertNil(body["reasoning"]?["summary"])
    }

    func testXaiResponsesMapsEffort() {
        let body = XaiModel.responsesBody(
            for: request(.minimal), modelID: "grok-4"
        ).objectValue ?? [:]
        XCTAssertEqual(body["reasoning"]?["effort"]?.stringValue, "low")

        let none = XaiModel.responsesBody(
            for: request(ReasoningEffort.none), modelID: "grok-4"
        ).objectValue ?? [:]
        XCTAssertEqual(none["reasoning"]?["effort"]?.stringValue, "none")

        let fixed = XaiModel.responsesBody(
            for: request(.high), modelID: "grok-4.20-reasoning"
        ).objectValue ?? [:]
        XCTAssertNil(fixed["reasoning"])
    }

    private func anthropicBody(
        _ reasoning: ReasoningEffort, modelID: String, maxOutputTokens: Int = 1024
    ) -> [String: JSONValue] {
        AnthropicModel.requestBody(
            for: request(reasoning, maxOutputTokens: maxOutputTokens), modelID: modelID
        ).objectValue ?? [:]
    }

    func testAnthropicAdaptiveThinkingWithEffort() {
        let body = anthropicBody(.high, modelID: "claude-sonnet-5")
        XCTAssertEqual(body["thinking"]?["type"]?.stringValue, "adaptive")
        XCTAssertEqual(body["output_config"]?["effort"]?.stringValue, "high")

        XCTAssertEqual(
            anthropicBody(.xhigh, modelID: "claude-sonnet-5")["output_config"]?["effort"]?.stringValue,
            "xhigh"
        )
        XCTAssertEqual(
            anthropicBody(.xhigh, modelID: "claude-opus-4-6")["output_config"]?["effort"]?.stringValue,
            "max"
        )
        XCTAssertEqual(
            anthropicBody(.minimal, modelID: "claude-sonnet-5")["output_config"]?["effort"]?.stringValue,
            "low"
        )
    }

    func testAnthropicBudgetThinkingOnOlderModels() {
        let body = anthropicBody(.medium, modelID: "claude-sonnet-4-5", maxOutputTokens: 2000)
        XCTAssertEqual(body["thinking"]?["type"]?.stringValue, "enabled")
        XCTAssertEqual(body["thinking"]?["budget_tokens"]?.intValue, 19200)
        XCTAssertEqual(body["max_tokens"]?.intValue, 21200)

        let haiku = anthropicBody(.minimal, modelID: "claude-3-haiku-20240307")
        XCTAssertEqual(haiku["thinking"]?["budget_tokens"]?.intValue, 1024)
        XCTAssertEqual(haiku["max_tokens"]?.intValue, 2048)
    }

    func testAnthropicNoneDisablesThinking() {
        let body = anthropicBody(ReasoningEffort.none, modelID: "claude-sonnet-5")
        XCTAssertEqual(body["thinking"]?["type"]?.stringValue, "disabled")
        XCTAssertNil(body["output_config"])
    }

    func testAnthropicProviderOptionsThinkingWins() {
        let body = AnthropicModel.requestBody(
            for: request(
                .high,
                providerOptions: .object([
                    "thinking": .object([
                        "type": .string("enabled"), "budget_tokens": .number(2048)
                    ])
                ])
            ),
            modelID: "claude-sonnet-5"
        ).objectValue ?? [:]
        XCTAssertEqual(body["thinking"]?["type"]?.stringValue, "enabled")
        XCTAssertEqual(body["thinking"]?["budget_tokens"]?.intValue, 2048)
    }

    private func googleThinking(
        _ reasoning: ReasoningEffort, modelID: String
    ) -> JSONValue? {
        let body = GoogleModel.requestBody(
            for: request(reasoning), modelID: modelID
        ).objectValue ?? [:]
        return body["generationConfig"]?["thinkingConfig"]
    }

    func testGemini3TakesThinkingLevels() {
        XCTAssertEqual(
            googleThinking(.high, modelID: "gemini-3.5-flash")?["thinkingLevel"]?.stringValue,
            "high"
        )
        XCTAssertEqual(
            googleThinking(.xhigh, modelID: "gemini-3.5-flash")?["thinkingLevel"]?.stringValue,
            "high"
        )
        XCTAssertEqual(
            googleThinking(ReasoningEffort.none, modelID: "gemini-3.5-flash")?["thinkingLevel"]?.stringValue,
            "minimal"
        )
    }

    func testGemini25TakesThinkingBudgets() {
        XCTAssertEqual(
            googleThinking(.medium, modelID: "gemini-2.5-pro")?["thinkingBudget"]?.intValue,
            19661
        )
        XCTAssertEqual(
            googleThinking(.xhigh, modelID: "gemini-2.5-flash")?["thinkingBudget"]?.intValue,
            24576
        )
        XCTAssertEqual(
            googleThinking(ReasoningEffort.none, modelID: "gemini-2.5-flash")?["thinkingBudget"]?.intValue,
            0
        )
        XCTAssertEqual(
            googleThinking(.xhigh, modelID: "gemini-3-pro-image")?["thinkingBudget"]?.intValue,
            32768
        )
    }

    func testBedrockClaudeAdaptiveAndBudgetPaths() {
        let adaptive = BedrockModel.requestBody(
            for: request(.xhigh), modelID: "us.anthropic.claude-sonnet-5-v1:0"
        ).objectValue ?? [:]
        let adaptiveFields = adaptive["additionalModelRequestFields"]
        XCTAssertEqual(adaptiveFields?["thinking"]?["type"]?.stringValue, "adaptive")
        XCTAssertEqual(adaptiveFields?["output_config"]?["effort"]?.stringValue, "max")

        let budget = BedrockModel.requestBody(
            for: request(.medium), modelID: "anthropic.claude-sonnet-4-5-20250929-v1:0"
        ).objectValue ?? [:]
        let budgetFields = budget["additionalModelRequestFields"]
        XCTAssertEqual(budgetFields?["thinking"]?["type"]?.stringValue, "enabled")
        XCTAssertEqual(budgetFields?["thinking"]?["budget_tokens"]?.intValue, 19200)
        XCTAssertEqual(
            budget["inferenceConfig"]?["maxTokens"]?.intValue, 1024 + 19200
        )
    }

    func testBedrockOpenAIAndGenericModels() {
        let openAI = BedrockModel.requestBody(
            for: request(.xhigh), modelID: "openai.gpt-oss-120b-1:0"
        ).objectValue ?? [:]
        XCTAssertEqual(
            openAI["additionalModelRequestFields"]?["reasoning_effort"]?.stringValue, "max"
        )

        let nova = BedrockModel.requestBody(
            for: request(.high), modelID: "amazon.nova-pro-v1:0"
        ).objectValue ?? [:]
        XCTAssertEqual(
            nova["additionalModelRequestFields"]?["reasoningConfig"]?["maxReasoningEffort"]?.stringValue,
            "high"
        )

        let off = BedrockModel.requestBody(
            for: request(ReasoningEffort.none), modelID: "amazon.nova-pro-v1:0"
        ).objectValue ?? [:]
        XCTAssertNil(off["additionalModelRequestFields"])
    }
}
