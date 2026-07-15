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

    func testGroqMapsEffortSendsNoneAndFormat() {
        XCTAssertEqual(
            chatBody(.xhigh, style: .groq)["reasoning_effort"]?.stringValue, "high"
        )
        XCTAssertEqual(
            chatBody(.minimal, style: .groq)["reasoning_effort"]?.stringValue, "low"
        )
        XCTAssertEqual(
            chatBody(.none, style: .groq)["reasoning_effort"]?.stringValue, "none"
        )
        XCTAssertEqual(
            chatBody(.high, style: .groq)["reasoning_format"]?.stringValue, "parsed"
        )
        XCTAssertNil(chatBody(.providerDefault, style: .groq)["reasoning_effort"])
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

    func testProviderMetadataAccumulatesOnResult() async throws {
        let model = MockLanguageModel(parts: [
            .textDelta("hi"),
            .providerMetadata(.object([
                "perplexity": .object([
                    "images": .array([.string("https://ex.com/a.jpg")]),
                    "related_questions": .array([.string("What next?")])
                ])
            ])),
            .finish(reason: .stop, usage: Usage())
        ])
        let result = try await generateText(model: model, prompt: "hi")
        let perplexity = result.providerMetadata?["perplexity"]
        XCTAssertEqual(perplexity?["images"]?.arrayValue?.first?.stringValue, "https://ex.com/a.jpg")
        XCTAssertEqual(
            perplexity?["related_questions"]?.arrayValue?.first?.stringValue, "What next?"
        )
    }

    func testProviderMetadataNilWhenAbsent() async throws {
        let model = MockLanguageModel(text: "hi")
        let result = try await generateText(model: model, prompt: "hi")
        XCTAssertNil(result.providerMetadata)
    }

    func testAlibabaMapsReasoningToThinkingBudget() {
        XCTAssertEqual(chatBody(.high, style: .alibaba)["enable_thinking"]?.boolValue, true)
        XCTAssertEqual(chatBody(.high, style: .alibaba)["thinking_budget"]?.intValue, 38912)
        XCTAssertEqual(chatBody(.low, style: .alibaba)["thinking_budget"]?.intValue, 4096)
        XCTAssertEqual(chatBody(.none, style: .alibaba)["enable_thinking"]?.boolValue, false)
        XCTAssertNil(chatBody(.none, style: .alibaba)["thinking_budget"])
        XCTAssertNil(chatBody(.providerDefault, style: .alibaba)["enable_thinking"])
    }

    func testTokenLimitKeyMatchesWire() {
        XCTAssertEqual(chatBody(.high, style: .openAI)["max_completion_tokens"]?.intValue, 1024)
        XCTAssertNil(chatBody(.high, style: .openAI)["max_tokens"])
        XCTAssertEqual(chatBody(.high, style: .compatible)["max_tokens"]?.intValue, 1024)
        XCTAssertNil(chatBody(.high, style: .compatible)["max_completion_tokens"])
    }

    func testSeedKeyMatchesWire() {
        let req = LanguageModelRequest(messages: [.user("hi")], maxOutputTokens: 1024, seed: 7)
        let mistral = OpenAIChatModel.requestBody(for: req, modelID: "m", reasoningStyle: .mistral)
            .objectValue ?? [:]
        XCTAssertEqual(mistral["random_seed"]?.intValue, 7)
        XCTAssertNil(mistral["seed"])
        let compat = OpenAIChatModel.requestBody(for: req, modelID: "m", reasoningStyle: .compatible)
            .objectValue ?? [:]
        XCTAssertEqual(compat["seed"]?.intValue, 7)
        XCTAssertNil(compat["random_seed"])
    }

    func testDeltaDecodesMistralArrayContent() throws {
        let json = """
        {"choices":[{"delta":{"content":[\
        {"type":"thinking","thinking":[{"type":"text","text":"weigh it"}]},\
        {"type":"text","text":"answer"}\
        ]}}]}
        """.data(using: .utf8)!
        let chunk = try JSONDecoder().decode(OpenAIChunk.self, from: json)
        let delta = chunk.choices?.first?.delta
        XCTAssertEqual(delta?.content, "answer")
        XCTAssertEqual(delta?.reasoning_content, "weigh it")
    }

    func testDeltaStillDecodesStringContent() throws {
        let json = #"{"choices":[{"delta":{"content":"plain"}}]}"#.data(using: .utf8)!
        let chunk = try JSONDecoder().decode(OpenAIChunk.self, from: json)
        XCTAssertEqual(chunk.choices?.first?.delta?.content, "plain")
    }

    func testOpenRouterSendsNestedReasoningObject() {
        XCTAssertEqual(
            chatBody(.xhigh, style: .openRouter)["reasoning"]?["effort"]?.stringValue, "high"
        )
        XCTAssertEqual(
            chatBody(.minimal, style: .openRouter)["reasoning"]?["effort"]?.stringValue, "low"
        )
        XCTAssertEqual(
            chatBody(.medium, style: .openRouter)["reasoning"]?["effort"]?.stringValue, "medium"
        )
        XCTAssertNil(chatBody(.none, style: .openRouter)["reasoning"])
        // Never a top-level reasoning_effort string — OpenRouter doesn't read that field.
        XCTAssertNil(chatBody(.xhigh, style: .openRouter)["reasoning_effort"])
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
        XCTAssertEqual(OpenAIChatModel.ReasoningWireStyle.forProvider("openrouter"), .openRouter)
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

    func testResponsesProviderOptionsMergeKeepsBuiltSubkeys() {
        let body = OpenAIModel.responsesBody(
            for: LanguageModelRequest(
                messages: [.user("hi")],
                reasoning: .high,
                responseFormat: .json(schema: .object(["type": .string("object")]), name: "Out"),
                providerOptions: .object([
                    "text": .object(["verbosity": .string("low")]),
                    "reasoning": .object(["summary": .string("auto")])
                ])
            ),
            modelID: "gpt-5.6"
        ).objectValue ?? [:]
        XCTAssertEqual(body["text"]?["verbosity"]?.stringValue, "low")
        XCTAssertEqual(body["text"]?["format"]?["name"]?.stringValue, "Out")
        XCTAssertEqual(body["reasoning"]?["effort"]?.stringValue, "high")
        XCTAssertEqual(body["reasoning"]?["summary"]?.stringValue, "auto")
    }

    func testXaiResponsesMapsEffort() {
        let body = XaiModel.responsesBody(
            for: request(.minimal), modelID: "grok-4"
        ).objectValue ?? [:]
        XCTAssertEqual(body["reasoning"]?["effort"]?.stringValue, "low")
        XCTAssertEqual(body["reasoning"]?["summary"]?.stringValue, "auto")

        let none = XaiModel.responsesBody(
            for: request(ReasoningEffort.none), modelID: "grok-4"
        ).objectValue ?? [:]
        XCTAssertEqual(none["reasoning"]?["effort"]?.stringValue, "none")
        XCTAssertNil(none["reasoning"]?["summary"])

        let fixed = XaiModel.responsesBody(
            for: request(.high), modelID: "grok-4.20-reasoning"
        ).objectValue ?? [:]
        XCTAssertNil(fixed["reasoning"])
    }

    func testXaiResponsesForwardsIncludeAndMaxTurns() {
        let body = XaiModel.responsesBody(
            for: request(
                .providerDefault,
                providerOptions: .object([
                    "include": .array([.string("reasoning.encrypted_content")]),
                    "max_turns": .number(6)
                ])
            ),
            modelID: "grok-4"
        ).objectValue ?? [:]
        XCTAssertEqual(body["include"]?.arrayValue?.first?.stringValue, "reasoning.encrypted_content")
        XCTAssertEqual(body["max_turns"]?.intValue, 6)
    }

    func testXaiResponsesProviderOptionsMergeKeepsEffort() {
        let body = XaiModel.responsesBody(
            for: request(
                .high,
                providerOptions: .object([
                    "reasoning": .object(["summary": .string("detailed")])
                ])
            ),
            modelID: "grok-4"
        ).objectValue ?? [:]
        XCTAssertEqual(body["reasoning"]?["effort"]?.stringValue, "high")
        XCTAssertEqual(body["reasoning"]?["summary"]?.stringValue, "detailed")
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
        XCTAssertEqual(
            googleThinking(.high, modelID: "gemini-3.5-flash")?["includeThoughts"]?.boolValue, true
        )
        XCTAssertEqual(
            googleThinking(ReasoningEffort.none, modelID: "gemini-3.5-flash")?["includeThoughts"]?.boolValue,
            false
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
        XCTAssertEqual(
            googleThinking(.medium, modelID: "gemini-2.5-pro")?["includeThoughts"]?.boolValue, true
        )
        XCTAssertEqual(
            googleThinking(ReasoningEffort.none, modelID: "gemini-2.5-flash")?["includeThoughts"]?.boolValue,
            false
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
