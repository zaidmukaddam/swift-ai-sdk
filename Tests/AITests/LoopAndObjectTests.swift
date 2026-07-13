import XCTest
@testable import AI

final class LoopAndObjectTests: XCTestCase {

    private func echoTool(_ name: String = "echo") -> Tool {
        Tool(name: name, description: "echoes", parameters: ["type": "object"]) { args in args }
    }

    private func toolCallScript(_ id: String, _ name: String) -> [StreamPart] {
        [.toolCall(ToolCall(id: id, name: name, arguments: ["n": 1])),
         .finish(reason: .toolCalls, usage: .init())]
    }

    func testStepCountIsBoundsTheLoop() async throws {
        let model = MockModel(scripts: [
            toolCallScript("t1", "echo"),
            toolCallScript("t2", "echo"),
            toolCallScript("t3", "echo")
        ])
        let result = try await generateText(
            model: model, messages: [.user("go")], tools: [echoTool()],
            stopWhen: [stepCountIs(2)]
        )
        XCTAssertEqual(result.stepCount, 2)
        XCTAssertEqual(result.finishReason, .toolCalls)
        XCTAssertEqual(result.toolResults.count, 2)
    }

    func testHasToolCallStopsImmediately() async throws {
        let model = MockModel(scripts: [
            toolCallScript("t1", "finalAnswer"),
            [.textDelta("should never run"), .finish(reason: .stop, usage: .init())]
        ])
        let result = try await generateText(
            model: model, messages: [.user("go")], tools: [echoTool("finalAnswer")],
            stopWhen: [hasToolCall("finalAnswer")]
        )
        XCTAssertEqual(result.stepCount, 1)
        XCTAssertEqual(result.toolCalls.first?.name, "finalAnswer")
    }

    func testPrepareStepCanRewriteMessagesAndModel() async throws {
        let modelA = MockModel(scripts: [toolCallScript("t1", "echo")])
        let modelB = MockModel(scripts: [
            [.textDelta("from B"), .finish(reason: .stop, usage: .init())]
        ])
        let result = try await generateText(
            model: modelA, messages: [.user("hello")], tools: [echoTool()],
            prepareStep: { context in
                guard context.stepNumber == 1 else { return nil }
                return PrepareStepResult(model: modelB, messages: [.user("compacted")])
            }
        )
        XCTAssertEqual(result.text, "from B")
        XCTAssertEqual(result.stepCount, 2)
    }

    func testOnStepFinishSeesEveryStep() async throws {
        let model = MockModel(scripts: [
            toolCallScript("t1", "echo"),
            [.textDelta("done"), .finish(reason: .stop, usage: .init())]
        ])
        let recorder = Recorder()
        _ = try await generateText(
            model: model, messages: [.user("go")], tools: [echoTool()],
            onStepFinish: { step in await recorder.append(step.finishReason) }
        )
        let reasons = await recorder.values
        XCTAssertEqual(reasons, [.toolCalls, .stop])
    }

    func testFullStreamEventOrderingAcrossSteps() async throws {
        let model = MockModel(scripts: [
            toolCallScript("t1", "echo"),
            [.textDelta("hi"), .finish(reason: .stop, usage: .init())]
        ])
        var events: [String] = []
        let result = streamText(model: model, messages: [.user("go")], tools: [echoTool()])
        for try await part in result.fullStream {
            switch part {
            case .startStep(let index): events.append("startStep(\(index))")
            case .toolCall: events.append("toolCall")
            case .toolResult: events.append("toolResult")
            case .textDelta: events.append("textDelta")
            case .finishStep: events.append("finishStep")
            case .finish: events.append("finish")
            default: break
            }
        }
        XCTAssertEqual(events, [
            "startStep(0)", "toolCall", "toolResult", "finishStep",
            "startStep(1)", "textDelta", "finishStep", "finish"
        ])
    }

    func testTextStreamYieldsOnlyDeltas() async throws {
        let model = MockModel(scripts: [
            [.textDelta("a"), .textDelta("b"), .finish(reason: .stop, usage: .init())]
        ])
        var collected = ""
        for try await delta in streamText(model: model, messages: [.user("x")]).textStream {
            collected += delta
        }
        XCTAssertEqual(collected, "ab")
    }

    func testSystemAndPromptAssembleMessages() async throws {
        let model = InspectingModel()
        _ = try await generateText(
            model: model, system: "You are terse.", prompt: "Say hi."
        )
        let request = await model.lastRequest()
        XCTAssertEqual(request?.messages.first?.role, .system)
        XCTAssertEqual(request?.messages.last?.text, "Say hi.")
    }

    struct Recipe: Codable, Equatable {
        var name: String
        var steps: [String]
    }

    private let recipeSchema: JSONValue = [
        "type": "object",
        "properties": [
            "name": ["type": "string"],
            "steps": ["type": "array", "items": ["type": "string"]]
        ],
        "required": ["name", "steps"]
    ]

    func testGenerateObjectFromTextJSON() async throws {
        let model = MockModel(scripts: [[
            .textDelta(#"{"name": "Lasagna", "#),
            .textDelta(#""steps": ["boil", "bake"]}"#),
            .finish(reason: .stop, usage: .init())
        ]])
        let result = try await generateObject(
            model: model, of: Recipe.self, schema: recipeSchema, prompt: "lasagna"
        )
        XCTAssertEqual(result.object, Recipe(name: "Lasagna", steps: ["boil", "bake"]))
    }

    func testGenerateObjectFromForcedToolCall() async throws {
        let model = MockModel(scripts: [[
            .toolCall(ToolCall(id: "t1", name: "response",
                               arguments: ["name": "Dal", "steps": ["simmer"]])),
            .finish(reason: .toolCalls, usage: .init())
        ]])
        let result = try await generateObject(
            model: model, of: Recipe.self, schema: recipeSchema, prompt: "dal"
        )
        XCTAssertEqual(result.object.name, "Dal")
    }

    func testGenerateObjectFailureThrowsNoObjectGenerated() async throws {
        let model = MockModel(scripts: [[
            .textDelta("I refuse to answer in JSON."),
            .finish(reason: .stop, usage: .init())
        ]])
        do {
            _ = try await generateObject(
                model: model, of: Recipe.self, schema: recipeSchema, prompt: "x"
            )
            XCTFail("expected noObjectGenerated")
        } catch AIError.noObjectGenerated {
        }
    }

    func testStreamObjectYieldsGrowingPartials() async throws {
        let model = MockModel(scripts: [[
            .textDelta(#"{"name": "La"#),
            .textDelta(#"sagna", "steps""#),
            .textDelta(#": ["boil"]}"#),
            .finish(reason: .stop, usage: .init())
        ]])
        var partials: [JSONValue] = []
        let result = streamObject(model: model, schema: recipeSchema, prompt: "lasagna")
        for try await partial in result.partialObjectStream {
            partials.append(partial)
        }
        XCTAssertEqual(partials.last, ["name": "Lasagna", "steps": ["boil"]])
        XCTAssertGreaterThan(partials.count, 1)
    }

    func testRetryRecoversFrom429() async throws {
        let model = FlakyModel(failuresBeforeSuccess: 2)
        let result = try await generateText(model: model, prompt: "hi", maxRetries: 2)
        XCTAssertEqual(result.text, "recovered")
    }

    func testRetryGivesUpAfterMaxRetries() async throws {
        let model = FlakyModel(failuresBeforeSuccess: 3)
        do {
            _ = try await generateText(model: model, prompt: "hi", maxRetries: 1)
            XCTFail("expected http error")
        } catch AIError.http(let status, _) {
            XCTAssertEqual(status, 429)
        }
    }

    func testNonRetryableErrorFailsFast() async throws {
        let model = FlakyModel(failuresBeforeSuccess: 5, status: 401)
        do {
            _ = try await generateText(model: model, prompt: "hi", maxRetries: 2)
            XCTFail("expected http error")
        } catch AIError.http(let status, _) {
            XCTAssertEqual(status, 401)
            let attempts = await model.attemptCount()
            XCTAssertEqual(attempts, 1)
        }
    }

    func testEmbedAndCosineSimilarity() async throws {
        let model = MockEmbeddingModel()
        let result = try await embed(model: model, value: "hello")
        XCTAssertEqual(result.embedding.count, 3)

        let many = try await embedMany(model: model, values: ["a", "b"])
        XCTAssertEqual(many.embeddings.count, 2)

        XCTAssertEqual(cosineSimilarity([1, 0], [1, 0]), 1.0, accuracy: 1e-9)
        XCTAssertEqual(cosineSimilarity([1, 0], [0, 1]), 0.0, accuracy: 1e-9)
        XCTAssertEqual(cosineSimilarity([1, 0], [-1, 0]), -1.0, accuracy: 1e-9)
    }
}

private actor Recorder {
    var values: [FinishReason] = []
    func append(_ value: FinishReason) { values.append(value) }
}

private actor RequestStore {
    var last: LanguageModelRequest?
    func set(_ request: LanguageModelRequest) { last = request }
}

private struct InspectingModel: LanguageModel {
    let provider = "inspect"
    let modelID = "inspect-1"
    private let store = RequestStore()

    func lastRequest() async -> LanguageModelRequest? { await store.last }

    func stream(_ request: LanguageModelRequest) async throws -> AsyncThrowingStream<StreamPart, Error> {
        await store.set(request)
        return AsyncThrowingStream { continuation in
            continuation.yield(.textDelta("ok"))
            continuation.yield(.finish(reason: .stop, usage: .init()))
            continuation.finish()
        }
    }
}

private struct FlakyModel: LanguageModel {
    let provider = "flaky"
    let modelID = "flaky-1"
    let failuresBeforeSuccess: Int
    var status: Int = 429
    private let counter = AttemptCounter()

    actor AttemptCounter {
        var value = 0
        func increment() -> Int { value += 1; return value }
    }

    func attemptCount() async -> Int { await counter.value }

    func stream(_ request: LanguageModelRequest) async throws -> AsyncThrowingStream<StreamPart, Error> {
        let attempt = await counter.increment()
        if attempt <= failuresBeforeSuccess {
            throw AIError.http(status: status, body: "try later")
        }
        return AsyncThrowingStream { continuation in
            continuation.yield(.textDelta("recovered"))
            continuation.yield(.finish(reason: .stop, usage: .init()))
            continuation.finish()
        }
    }
}

private struct MockEmbeddingModel: EmbeddingModel {
    let provider = "mock"
    let modelID = "mock-embed"

    func embed(_ texts: [String]) async throws -> EmbeddingResponse {
        EmbeddingResponse(
            embeddings: texts.map { text in [Double(text.count), 1, 0] },
            usage: Usage(inputTokens: texts.count, outputTokens: 0)
        )
    }
}
