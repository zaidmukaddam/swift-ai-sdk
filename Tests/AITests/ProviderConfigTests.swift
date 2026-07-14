import XCTest
@testable import AI

final class ProviderConfigTests: XCTestCase {

    func testFirstClassCompatibleModelDefaults() {
        let expected: [(OpenAIChatModel, String, String)] = [
            (TogetherAIModel("m", apiKey: "k").engine,
             "togetherai", "https://api.together.xyz/v1/chat/completions"),
            (FireworksModel("m", apiKey: "k").engine,
             "fireworks", "https://api.fireworks.ai/inference/v1/chat/completions"),
            (CerebrasModel("m", apiKey: "k").engine,
             "cerebras", "https://api.cerebras.ai/v1/chat/completions"),
            (OpenRouterModel("m", apiKey: "k").engine,
             "openrouter", "https://openrouter.ai/api/v1/chat/completions"),
            (DeepInfraModel("m", apiKey: "k").engine,
             "deepinfra", "https://api.deepinfra.com/v1/openai/chat/completions"),
            (BasetenModel("m", apiKey: "k").engine,
             "baseten", "https://inference.baseten.co/v1/chat/completions"),
            (VercelModel("m", apiKey: "k").engine,
             "vercel", "https://api.v0.dev/v1/chat/completions"),
            (AIGatewayModel("m", apiKey: "k").engine,
             "gateway", "https://ai-gateway.vercel.sh/v1/chat/completions"),
            (SarvamModel("m", apiKey: "k").engine,
             "sarvam", "https://api.sarvam.ai/v1/chat/completions"),
            (OllamaModel("m").engine,
             "ollama", "http://localhost:11434/v1/chat/completions"),
            (LMStudioModel("m").engine,
             "lmstudio", "http://localhost:1234/v1/chat/completions")
        ]
        for (engine, provider, url) in expected {
            XCTAssertEqual(engine.provider, provider)
            XCTAssertEqual(engine.requestURL(path: "chat/completions").absoluteString, url)
        }
    }

    func testTogetherAIModelCarriesProviderNameAndURL() {
        let llama = TogetherAIModel("llama-3.3", apiKey: "k")
        XCTAssertEqual(llama.provider, "togetherai")
        XCTAssertEqual(llama.modelID, "llama-3.3")
        XCTAssertEqual(
            llama.engine.requestURL(path: "chat/completions").absoluteString,
            "https://api.together.xyz/v1/chat/completions"
        )
    }

    func testQueryParamsAppendToRequestURL() {
        let gateway = OpenAICompatibleProvider(
            name: "gw",
            baseURL: URL(string: "https://example.com/v1")!,
            apiKey: "k",
            queryParams: ["api-version": "2026-01-01"]
        )
        XCTAssertEqual(
            gateway("m").requestURL(path: "chat/completions").absoluteString,
            "https://example.com/v1/chat/completions?api-version=2026-01-01"
        )
    }

    func testCustomProviderVendsEmbeddingModels() {
        let embed = OpenAICompatibleProvider(
            name: "togetherai",
            baseURL: URL(string: "https://api.together.xyz/v1")!,
            apiKey: "k"
        )
            .textEmbeddingModel("BAAI/bge-large-en-v1.5")
        XCTAssertEqual(embed.provider, "togetherai")
        XCTAssertEqual(embed.modelID, "BAAI/bge-large-en-v1.5")
    }

    func testNativePackConfigs() {
        let groq = GroqModel("m", apiKey: "k")
        XCTAssertEqual(groq.provider, "groq")
        XCTAssertEqual(
            groq.engine.requestURL(path: "chat/completions").absoluteString,
            "https://api.groq.com/openai/v1/chat/completions"
        )

        let deepseek = DeepSeekModel("m", apiKey: "k")
        XCTAssertEqual(deepseek.provider, "deepseek")
        XCTAssertEqual(
            deepseek.engine.requestURL(path: "chat/completions").absoluteString,
            "https://api.deepseek.com/chat/completions"
        )

        let mistral = MistralModel("m", apiKey: "k")
        XCTAssertEqual(mistral.provider, "mistral")
        XCTAssertEqual(
            mistral.engine.requestURL(path: "chat/completions").absoluteString,
            "https://api.mistral.ai/v1/chat/completions"
        )

        let perplexity = PerplexityModel("m", apiKey: "k")
        XCTAssertEqual(perplexity.provider, "perplexity")
        XCTAssertEqual(
            perplexity.engine.requestURL(path: "chat/completions").absoluteString,
            "https://api.perplexity.ai/chat/completions"
        )
    }

    private func mappedUsage(_ json: String) throws -> Usage {
        let wire = try JSONDecoder().decode(OpenAIChunk.Usage.self, from: Data(json.utf8))
        return OpenAIChatModel.mapUsage(wire)
    }

    func testDeepSeekCacheHitTokensSurfaceAsCachedInputTokens() throws {
        let usage = try mappedUsage(#"""
        {"prompt_tokens": 30, "completion_tokens": 12, "prompt_cache_hit_tokens": 24,
         "prompt_cache_miss_tokens": 6}
        """#)
        XCTAssertEqual(usage.inputTokens, 30)
        XCTAssertEqual(usage.outputTokens, 12)
        XCTAssertEqual(usage.cachedInputTokens, 24)
    }

    func testOpenAIStandardCachedTokensPreferredOverDeepSeekField() throws {
        let usage = try mappedUsage(#"""
        {"prompt_tokens": 30, "prompt_tokens_details": {"cached_tokens": 20},
         "prompt_cache_hit_tokens": 24,
         "completion_tokens_details": {"reasoning_tokens": 7}}
        """#)
        XCTAssertEqual(usage.cachedInputTokens, 20)
        XCTAssertEqual(usage.reasoningTokens, 7)
    }

    func testUsageWithoutCacheFieldsLeavesCachedNil() throws {
        let usage = try mappedUsage(#"{"prompt_tokens": 5, "completion_tokens": 3}"#)
        XCTAssertNil(usage.cachedInputTokens)
    }
}

final class SourceFlowTests: XCTestCase {

    private func scriptedModel() -> MockModel {
        MockModel(scripts: [[
            .source(Source(id: "s1", url: "https://example.com", title: "Example")),
            .textDelta("hi"),
            .finish(reason: .stop, usage: .init())
        ]])
    }

    func testGenerateTextCollectsSources() async throws {
        let result = try await generateText(model: scriptedModel(), messages: [.user("x")])
        XCTAssertEqual(
            result.sources,
            [Source(id: "s1", url: "https://example.com", title: "Example")]
        )
    }

    func testSourcesSurfaceOnTheUIMessageStream() async throws {
        let stream = streamText(model: scriptedModel(), messages: [.user("x")])
        var types: [String] = []
        for try await chunk in UIMessageStream.chunks(from: stream.fullStream) {
            types.append(chunk.wire["type"]!.stringValue!)
        }
        XCTAssertTrue(types.contains("start-step"), "got \(types)")
        XCTAssertTrue(types.contains("source-url"), "got \(types)")
        XCTAssertTrue(types.contains("text-start"), "got \(types)")
    }
}
