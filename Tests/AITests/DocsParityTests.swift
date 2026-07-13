import XCTest
@testable import AI
import AITesting

final class DocsParityTests: XCTestCase {

    final class SeenOptions: @unchecked Sendable {
        var toolCallID: String?
        var messageCount = 0
        var context: JSONValue?
    }

    func testToolExecuteReceivesOptionsAndContext() async throws {
        let seen = SeenOptions()
        let lookup = Tool(
            name: "lookup",
            description: "Looks things up for one user.",
            parameters: .object(["type": .string("object")])
        ) { _, options in
            seen.toolCallID = options.toolCallID
            seen.messageCount = options.messages.count
            seen.context = options.context
            return .string("found")
        }

        let model = MockModel(scripts: [
            [
                .toolCall(ToolCall(id: "call-1", name: "lookup", arguments: .object([:]))),
                .finish(reason: .toolCalls, usage: .init())
            ],
            [
                .textDelta("done"),
                .finish(reason: .stop, usage: .init())
            ]
        ])
        let result = try await generateText(
            model: model,
            messages: [.user("look it up")],
            tools: [lookup],
            toolsContext: ["lookup": .object(["userID": .string("user-7")])]
        )
        XCTAssertEqual(result.text, "done")
        XCTAssertEqual(seen.toolCallID, "call-1")
        XCTAssertGreaterThan(seen.messageCount, 0)
        XCTAssertEqual(seen.context?["userID"]?.stringValue, "user-7")
    }

    func testPlainToolsIgnoreContextUnchanged() async throws {
        let model = MockModel(scripts: [
            [
                .toolCall(ToolCall(id: "c1", name: "plain", arguments: .object([:]))),
                .finish(reason: .toolCalls, usage: .init())
            ],
            [.textDelta("ok"), .finish(reason: .stop, usage: .init())]
        ])
        let plain = Tool(
            name: "plain", description: "No options.",
            parameters: .object(["type": .string("object")])
        ) { _ in .string("ran") }
        let result = try await generateText(
            model: model, messages: [.user("go")], tools: [plain],
            toolsContext: ["plain": .string("ignored")]
        )
        XCTAssertEqual(result.steps[0].toolResults[0].output.stringValue, "ran")
        XCTAssertEqual(result.text, "ok")
    }

    func testCustomProviderAliasAndFallback() throws {
        let base = ProviderRegistry.Provider { MockLanguageModel(text: "base \($0)") }
        let custom = customProvider(
            languageModels: ["fast": MockLanguageModel(modelID: "actual-fast", text: "hi")],
            fallback: base
        )
        let registry = ProviderRegistry(providers: ["p": custom])

        let alias = try registry.languageModel("p:fast")
        XCTAssertEqual(alias.modelID, "actual-fast")

        let fellBack = try registry.languageModel("p:other-model")
        XCTAssertEqual(fellBack.provider, "mock")
    }

    func testCustomProviderWithoutFallbackThrowsOnUnknownID() {
        let custom = customProvider(
            languageModels: ["fast": MockLanguageModel(text: "hi")]
        )
        let registry = ProviderRegistry(providers: ["p": custom])
        XCTAssertThrowsError(try registry.languageModel("p:missing"))
        XCTAssertThrowsError(try registry.embeddingModel("p:embed"))
    }

    func testAgentAsToolDelegatesToSubagent() async throws {
        let subModel = MockModel(scripts: [[
            .textDelta("subagent says 42"),
            .finish(reason: .stop, usage: .init())
        ]])
        let researcher = Agent(model: subModel, instructions: "You research.")

        let orchestratorModel = MockModel(scripts: [
            [
                .toolCall(ToolCall(
                    id: "t1", name: "researcher",
                    arguments: .object(["prompt": .string("what is the answer")])
                )),
                .finish(reason: .toolCalls, usage: .init())
            ],
            [.textDelta("relayed"), .finish(reason: .stop, usage: .init())]
        ])
        let orchestrator = Agent(
            model: orchestratorModel,
            tools: [researcher.asTool(
                name: "researcher", description: "Delegate research."
            )]
        )
        let result = try await orchestrator.generate(prompt: "delegate this")
        XCTAssertEqual(
            result.steps[0].toolResults[0].output.stringValue, "subagent says 42"
        )
        XCTAssertEqual(result.text, "relayed")
    }

    func testAgentAsToolRejectsMissingPrompt() async throws {
        let agent = Agent(model: MockModel(scripts: []))
        let tool = agent.asTool(name: "sub", description: "d")
        do {
            _ = try await tool.execute(.object([:]))
            XCTFail("expected an error")
        } catch {
            XCTAssertTrue("\(error)".contains("prompt"))
        }
    }

    func testBuildWritesAndMergesChunks() async throws {
        let inner = simulateReadableStream(chunks: [
            UIMessageChunk.start(messageID: "m1"),
            .textStart(id: "t1"),
            .textDelta(id: "t1", delta: "hello"),
            .textEnd(id: "t1"),
            .finish(finishReason: .stop)
        ])
        let stream = UIMessageStream.build { writer in
            writer.write(.data(name: "data-status", data: .string("working")))
            writer.merge(inner)
        }
        var chunks: [UIMessageChunk] = []
        for try await chunk in stream { chunks.append(chunk) }

        guard case .data(let name, _, let payload, _) = chunks[0] else {
            return XCTFail("expected the written data chunk first, got \(chunks[0])")
        }
        XCTAssertEqual(name, "data-status")
        XCTAssertEqual(payload.stringValue, "working")
        guard case .finish = chunks.last else {
            return XCTFail("expected finish last, got \(String(describing: chunks.last))")
        }
        XCTAssertEqual(chunks.count, 6)
    }

    func testBuildSurfacesBodyErrorsInBand() async throws {
        struct Boom: Error {}
        let stream = UIMessageStream.build(
            onError: { _ in "masked" }
        ) { writer in
            writer.write(.startStep)
            throw Boom()
        }
        var chunks: [UIMessageChunk] = []
        for try await chunk in stream { chunks.append(chunk) }
        guard case .error(let text) = chunks.last else {
            return XCTFail("expected trailing error chunk")
        }
        XCTAssertEqual(text, "masked")
    }

    func testReadUIMessageStreamYieldsSnapshots() async throws {
        let chunks = simulateReadableStream(chunks: [
            UIMessageChunk.start(messageID: "m1"),
            .textStart(id: "t1"),
            .textDelta(id: "t1", delta: "Hel"),
            .textDelta(id: "t1", delta: "lo"),
            .textEnd(id: "t1"),
            .finish(finishReason: .stop)
        ])
        var snapshots: [UIMessage] = []
        for try await message in readUIMessageStream(chunks) {
            snapshots.append(message)
        }
        XCTAssertEqual(snapshots.count, 6)
        XCTAssertEqual(snapshots.last?.id, "m1")
        XCTAssertEqual(snapshots.last?.text, "Hello")
        XCTAssertEqual(snapshots[2].text, "Hel")
    }

    func testChunksCarryStartAndStreamedMetadata() async throws {
        let model = MockModel(scripts: [[
            .textDelta("hi"),
            .finish(reason: .stop, usage: Usage(inputTokens: 2, outputTokens: 7))
        ]])
        let result = streamText(model: model, prompt: "hello")
        let chunks = UIMessageStream.chunks(
            from: result.fullStream,
            messageID: "m9",
            metadata: .object(["model": .string("mock-1")]),
            messageMetadata: { part in
                if case .finish(_, let usage) = part {
                    return .object(["outputTokens": .number(Double(usage.outputTokens))])
                }
                return nil
            }
        )
        var reducer = UIMessageReducer(messageID: "m9")
        for try await chunk in chunks { reducer.apply(chunk) }
        XCTAssertEqual(reducer.message.metadata?["model"]?.stringValue, "mock-1")
        XCTAssertEqual(reducer.message.metadata?["outputTokens"]?.intValue, 7)
        XCTAssertEqual(reducer.message.text, "hi")
    }

    func testMockLanguageModelRecordsRequestsAndStreamsText() async throws {
        let model = MockLanguageModel(text: "Hello, world!")
        let result = try await generateText(model: model, prompt: "Hi")
        XCTAssertEqual(result.text, "Hello, world!")
        XCTAssertEqual(model.requests.count, 1)
        XCTAssertEqual(model.requests[0].messages.last?.text, "Hi")
    }

    func testMockLanguageModelSequentialResponses() async throws {
        let model = MockLanguageModel(responses: [
            [
                .toolCall(ToolCall(id: "c1", name: "noop", arguments: .object([:]))),
                .finish(reason: .toolCalls, usage: .init())
            ],
            [.textDelta("after tool"), .finish(reason: .stop, usage: .init())]
        ])
        let noop = Tool(
            name: "noop", description: "d",
            parameters: .object(["type": .string("object")])
        ) { _ in .string("ok") }
        let result = try await generateText(model: model, prompt: "go", tools: [noop])
        XCTAssertEqual(result.text, "after tool")
        XCTAssertEqual(result.stepCount, 2)
        XCTAssertEqual(model.requests.count, 2)
    }

    func testMockEmbeddingModelCyclesVectors() async throws {
        let model = MockEmbeddingModel(vectors: [[1, 0], [0, 1]])
        let result = try await embedMany(
            model: model, values: ["a", "b", "c"]
        )
        XCTAssertEqual(result.embeddings.count, 3)
        XCTAssertEqual(result.embeddings[0], [1, 0])
        XCTAssertEqual(result.embeddings[2], [1, 0])
        XCTAssertEqual(model.batches, [["a", "b", "c"]])
    }

    func testSimulateReadableStreamPreservesOrder() async throws {
        let stream = simulateReadableStream(
            chunks: [1, 2, 3], chunkDelay: .milliseconds(1)
        )
        var out: [Int] = []
        for try await n in stream { out.append(n) }
        XCTAssertEqual(out, [1, 2, 3])
    }

    func testMockValuesSticksAtLast() {
        let next = mockValues("a", "b")
        XCTAssertEqual(next(), "a")
        XCTAssertEqual(next(), "b")
        XCTAssertEqual(next(), "b")
    }
}
