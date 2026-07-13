import XCTest
@testable import AI

final class ParityCompletionTests: XCTestCase {

    func testUsageAdditionPreservesDetail() {
        let a = Usage(inputTokens: 10, outputTokens: 5, cachedInputTokens: 4, reasoningTokens: 2)
        let b = Usage(inputTokens: 20, outputTokens: 10)
        let sum = a + b
        XCTAssertEqual(sum.inputTokens, 30)
        XCTAssertEqual(sum.cachedInputTokens, 4)
        XCTAssertEqual(sum.reasoningTokens, 2)
        XCTAssertNil((b + b).cachedInputTokens)
    }

    func testGenerateJSONWithoutSchema() async throws {
        let model = MockModel(scripts: [[
            .textDelta(#"{"anything": ["goes", 1, true]}"#),
            .finish(reason: .stop, usage: .init())
        ]])
        let result = try await generateJSON(model: model, prompt: "free-form")
        XCTAssertEqual(result.object["anything"]?.arrayValue?.count, 3)
    }

    func testGenerateEnumExtractsWrappedResult() async throws {
        let model = MockModel(scripts: [[
            .textDelta(#"{"result": "negative"}"#),
            .finish(reason: .stop, usage: .init())
        ]])
        let result = try await generateEnum(
            model: model,
            values: ["positive", "negative", "neutral"],
            prompt: "Classify: this is terrible."
        )
        XCTAssertEqual(result.value, "negative")
    }

    func testGenerateEnumRejectsValuesOutsideTheSet() async throws {
        let model = MockModel(scripts: [[
            .textDelta(#"{"result": "lukewarm"}"#),
            .finish(reason: .stop, usage: .init())
        ]])
        do {
            _ = try await generateEnum(model: model, values: ["hot", "cold"], prompt: "x")
            XCTFail("expected noObjectGenerated")
        } catch AIError.noObjectGenerated {}
    }

    func testJsonNoSchemaMapsToNativeJSONModes() {
        let request = LanguageModelRequest(messages: [.user("x")], responseFormat: .jsonNoSchema)
        XCTAssertEqual(
            OpenAIChatModel.requestBody(for: request, modelID: "gpt-4o")["response_format"]?["type"],
            "json_object"
        )
        XCTAssertEqual(
            XaiModel.responsesBody(for: request, modelID: "grok-4")["text"]?["format"]?["type"],
            "json_object"
        )
        XCTAssertEqual(
            GoogleModel.requestBody(for: request)["generationConfig"]?["responseMimeType"],
            "application/json"
        )
        XCTAssertEqual(
            CohereModel.requestBody(for: request, modelID: "command-r")["response_format"]?["type"],
            "json_object"
        )
    }

    func testRegistryResolvesCombinedIDs() throws {
        let registry = ProviderRegistry(providers: [
            "anthropic": .init { AnthropicModel($0, apiKey: "k") },
            "cohere": .init(
                languageModel: { CohereModel($0, apiKey: "k") },
                rerankingModel: { CohereRerankingModel($0, apiKey: "k") }
            )
        ])
        let claude = try registry.languageModel("anthropic:claude-sonnet-5")
        XCTAssertEqual(claude.provider, "anthropic")
        XCTAssertEqual(claude.modelID, "claude-sonnet-5")

        let reranker = try registry.rerankingModel("cohere:rerank-v3.5")
        XCTAssertEqual(reranker.modelID, "rerank-v3.5")

        XCTAssertThrowsError(try registry.languageModel("unknown:model"))
        XCTAssertThrowsError(try registry.languageModel("missing-separator"))
        XCTAssertThrowsError(try registry.embeddingModel("anthropic:x"))
    }

    func testRegistryCustomSeparator() throws {
        let registry = ProviderRegistry(
            providers: ["groq": .init { GroqModel($0, apiKey: "k") }],
            separator: "/"
        )
        XCTAssertEqual(
            try registry.languageModel("groq/llama-3.3-70b-versatile").modelID,
            "llama-3.3-70b-versatile"
        )
    }

    func testImageEditsGoMultipartToEditsEndpoint() throws {
        let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        let model = OpenAIImageModel("gpt-image-1", apiKey: "k")
        let urlRequest = try model.buildURLRequest(ImageModelRequest(
            prompt: "make it night", images: [ImageContent(data: png)]
        ))
        XCTAssertEqual(
            urlRequest.url?.absoluteString, "https://api.openai.com/v1/images/edits"
        )
        let contentType = urlRequest.value(forHTTPHeaderField: "content-type") ?? ""
        XCTAssertTrue(contentType.hasPrefix("multipart/form-data; boundary="))
        let body = String(decoding: urlRequest.httpBody ?? Data(), as: UTF8.self)
        XCTAssertTrue(body.contains("name=\"image[]\""))
        XCTAssertTrue(body.contains("name=\"prompt\""))

        let plain = try model.buildURLRequest(ImageModelRequest(prompt: "a fox"))
        XCTAssertEqual(
            plain.url?.absoluteString, "https://api.openai.com/v1/images/generations"
        )
    }

    func testTypedSearchParametersWireShape() {
        let search = XaiModel.SearchParameters(
            mode: .auto,
            returnCitations: true,
            fromDate: "2026-07-01",
            maxSearchResults: 10,
            sources: [
                .web(country: "US", excludedWebsites: ["example.com"]),
                .x(includedHandles: ["xai"]),
                .news(country: "GB")
            ]
        )
        let value = search.jsonValue
        XCTAssertEqual(value["mode"], "auto")
        XCTAssertEqual(value["return_citations"], true)
        XCTAssertEqual(value["from_date"], "2026-07-01")
        XCTAssertEqual(value["max_search_results"]?.intValue, 10)
        let sources = value["sources"]?.arrayValue
        XCTAssertEqual(sources?.count, 3)
        XCTAssertEqual(sources?[0]["type"], "web")
        XCTAssertEqual(sources?[0]["excluded_websites"]?.arrayValue?.first, "example.com")
        XCTAssertEqual(sources?[1]["included_x_handles"]?.arrayValue?.first, "xai")
        XCTAssertEqual(sources?[2]["type"], "news")
        XCTAssertEqual(
            search.providerOptions["search_parameters"]?["mode"], "auto"
        )
    }
}

@MainActor
final class ResumeStreamTests: XCTestCase {

    struct ResumableTransport: ChatTransport {
        var activeChatID: String

        func sendMessages(_ request: ChatRequest) async throws -> AsyncThrowingStream<UIMessageChunk, Error> {
            AsyncThrowingStream { $0.finish() }
        }

        func reconnectToStream(chatID: String) async throws -> AsyncThrowingStream<UIMessageChunk, Error>? {
            guard chatID == activeChatID else { return nil }
            return AsyncThrowingStream { continuation in
                continuation.yield(.start(messageID: "resumed"))
                continuation.yield(.textStart(id: "t"))
                continuation.yield(.textDelta(id: "t", delta: "picking back up"))
                continuation.yield(.textEnd(id: "t"))
                continuation.yield(.finish(finishReason: .stop))
                continuation.finish()
            }
        }
    }

    func testResumeStreamAttachesToActiveResponse() async throws {
        guard #available(macOS 14.0, iOS 17.0, *) else { throw XCTSkip("needs Observation") }

        let chat = ChatSession(transport: ResumableTransport(activeChatID: "c1"), id: "c1")
        chat.resumeStream()
        try await settle(chat)
        XCTAssertEqual(chat.messages.last?.text, "picking back up")
        XCTAssertEqual(chat.messages.last?.id, "resumed")
    }

    func testResumeStreamNoOpWhenNothingActive() async throws {
        guard #available(macOS 14.0, iOS 17.0, *) else { throw XCTSkip("needs Observation") }

        let chat = ChatSession(transport: ResumableTransport(activeChatID: "other"), id: "c1")
        chat.resumeStream()
        try await settle(chat)
        XCTAssertTrue(chat.messages.isEmpty)
        XCTAssertEqual(chat.status, .ready)
    }

    @available(macOS 14.0, iOS 17.0, *)
    private func settle(_ chat: ChatSession, timeout: TimeInterval = 2) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        try await Task.sleep(nanoseconds: 10_000_000)
        while chat.isLoading {
            if Date() > deadline { throw XCTSkip("did not settle") }
            try await Task.sleep(nanoseconds: 5_000_000)
        }
    }
}
