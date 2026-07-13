import XCTest
@testable import AI

final class MiddlewareTests: XCTestCase {

    func testExtractReasoningSplitsTagsAcrossDeltaBoundaries() async throws {
        let model = ScriptedModel(parts: [
            .textDelta("Hi <th"),
            .textDelta("ink>po"),
            .textDelta("nder</thi"),
            .textDelta("nk> bye"),
            .finish(reason: .stop, usage: .init())
        ])
        let wrapped = wrapLanguageModel(model: model, middleware: [.extractReasoning()])
        let parts = try await collect(wrapped.stream(LanguageModelRequest(messages: [.user("x")])))

        XCTAssertEqual(joinedText(parts), "Hi  bye")
        XCTAssertEqual(joinedReasoning(parts), "ponder")
        guard let last = parts.last, case .finish = last else {
            return XCTFail("expected finish as last part")
        }
    }

    func testExtractReasoningFlushesUnterminatedTagPrefixAsText() async throws {
        let model = ScriptedModel(parts: [
            .textDelta("a <thi"),
            .finish(reason: .stop, usage: .init())
        ])
        let wrapped = wrapLanguageModel(model: model, middleware: [.extractReasoning()])
        let parts = try await collect(wrapped.stream(LanguageModelRequest(messages: [.user("x")])))

        XCTAssertEqual(joinedText(parts), "a <thi")
        XCTAssertEqual(joinedReasoning(parts), "")
    }

    func testExtractReasoningHonorsCustomTag() async throws {
        let model = ScriptedModel(parts: [
            .textDelta("<scratch>plan</scr"),
            .textDelta("atch>answer"),
            .finish(reason: .stop, usage: .init())
        ])
        let wrapped = wrapLanguageModel(
            model: model, middleware: [.extractReasoning(tag: "scratch")]
        )
        let parts = try await collect(wrapped.stream(LanguageModelRequest(messages: [.user("x")])))

        XCTAssertEqual(joinedReasoning(parts), "plan")
        XCTAssertEqual(joinedText(parts), "answer")
    }

    func testDefaultSettingsOnlyFillsUnsetFields() async throws {
        let model = ScriptedModel(parts: [.finish(reason: .stop, usage: .init())])
        let wrapped = wrapLanguageModel(model: model, middleware: [
            .defaultSettings(
                temperature: 0.5,
                topP: 0.9,
                maxOutputTokens: 2048,
                providerOptions: ["a": 1, "nested": ["x": 1]]
            )
        ])

        var request = LanguageModelRequest(messages: [.user("x")])
        request.temperature = 0.1
        request.providerOptions = ["a": 99, "b": 2]
        _ = try await collect(wrapped.stream(request))

        let captured = await model.lastRequest()
        let seen = try XCTUnwrap(captured)
        XCTAssertEqual(seen.temperature, 0.1)
        XCTAssertEqual(seen.topP, 0.9)
        XCTAssertEqual(seen.maxOutputTokens, 2048)
        XCTAssertEqual(seen.providerOptions, ["a": 99, "b": 2, "nested": ["x": 1]])
    }

    func testDefaultSettingsKeepsExplicitMaxOutputTokens() async throws {
        let model = ScriptedModel(parts: [.finish(reason: .stop, usage: .init())])
        let wrapped = wrapLanguageModel(
            model: model, middleware: [.defaultSettings(maxOutputTokens: 2048)]
        )
        var request = LanguageModelRequest(messages: [.user("x")])
        request.maxOutputTokens = 512
        _ = try await collect(wrapped.stream(request))

        let captured = await model.lastRequest()
        let seen = try XCTUnwrap(captured)
        XCTAssertEqual(seen.maxOutputTokens, 512)
    }

    func testWrapOrderMatchesAIv7() async throws {
        let model = ScriptedModel(parts: [
            .textDelta("x"),
            .finish(reason: .stop, usage: .init())
        ])
        let wrapped = wrapLanguageModel(
            model: model, middleware: [markerMiddleware("A"), markerMiddleware("B")]
        )
        let parts = try await collect(wrapped.stream(LanguageModelRequest(messages: [.user("go")])))

        let captured = await model.lastRequest()
        let seen = try XCTUnwrap(captured)
        XCTAssertEqual(seen.stopSequences, ["A", "B"])
        XCTAssertEqual(joinedText(parts), "xBA")
    }

    func testSimulateStreamingBuffersAndCoalescesDeltas() async throws {
        let call = ToolCall(id: "t1", name: "echo", arguments: ["n": 1])
        let model = ScriptedModel(parts: [
            .textDelta("Hel"),
            .textDelta("lo"),
            .toolCall(call),
            .textDelta("!"),
            .finish(reason: .stop, usage: .init())
        ])
        let wrapped = wrapLanguageModel(model: model, middleware: [.simulateStreaming()])
        let parts = try await collect(wrapped.stream(LanguageModelRequest(messages: [.user("x")])))

        var shape: [String] = []
        for part in parts {
            switch part {
            case .textDelta(let t): shape.append("text(\(t))")
            case .toolCall(let c): shape.append("toolCall(\(c.name))")
            case .finish: shape.append("finish")
            default: shape.append("other")
            }
        }
        XCTAssertEqual(shape, ["text(Hello)", "toolCall(echo)", "text(!)", "finish"])
    }

    func testEmbedManyBatchingMath() async throws {
        let model = CountingEmbeddingModel()
        let result = try await embedMany(
            model: model,
            values: ["a", "bb", "ccc", "dddd", "eeeee"],
            maxBatchSize: 2
        )

        let sizes = await model.batchSizes()
        XCTAssertEqual(sizes, [2, 2, 1])
        XCTAssertEqual(result.embeddings, [[1], [2], [3], [4], [5]])
        XCTAssertEqual(result.usage.inputTokens, 5)
    }

    func testEmbedManyWithoutBatchSizeMakesOneCall() async throws {
        let model = CountingEmbeddingModel()
        let result = try await embedMany(model: model, values: ["a", "bb", "ccc"])

        let sizes = await model.batchSizes()
        XCTAssertEqual(sizes, [3])
        XCTAssertEqual(result.embeddings.count, 3)
    }

    func testElementStreamYieldsEachCompletedElementExactlyOnce() async throws {
        let model = ScriptedModel(parts: [
            .textDelta(#"[{"a": 1"#),
            .textDelta(#"}, {"a": 2}"#),
            .textDelta(#", {"a": 3}]"#),
            .finish(reason: .stop, usage: .init())
        ])
        let result = streamObject(
            model: model,
            schema: ["type": "array", "items": ["type": "object"]],
            prompt: "three items"
        )

        var elements: [JSONValue] = []
        for try await element in result.elementStream() {
            elements.append(element)
        }
        XCTAssertEqual(elements, [["a": 1], ["a": 2], ["a": 3]])
    }

    func testCacheHitReplaysWithoutCallingModel() async throws {
        let counter = CallCounter()
        let model = CountingModel(
            parts: [.textDelta("hi"), .finish(reason: .stop, usage: .init())], counter: counter
        )
        let wrapped = wrapLanguageModel(model: model, middleware: [.cache()])
        let request = LanguageModelRequest(messages: [.user("x")])

        let first = try await collect(wrapped.stream(request))
        let second = try await collect(wrapped.stream(request))

        XCTAssertEqual(joinedText(first), "hi")
        XCTAssertEqual(joinedText(second), "hi")
        XCTAssertEqual(counter.count, 1)
    }

    func testCacheMissesOnDifferentRequest() async throws {
        let counter = CallCounter()
        let model = CountingModel(
            parts: [.textDelta("hi"), .finish(reason: .stop, usage: .init())], counter: counter
        )
        let wrapped = wrapLanguageModel(model: model, middleware: [.cache()])

        _ = try await collect(wrapped.stream(LanguageModelRequest(messages: [.user("a")])))
        _ = try await collect(wrapped.stream(LanguageModelRequest(messages: [.user("b")])))

        XCTAssertEqual(counter.count, 2)
    }

    func testCacheDoesNotStoreErrors() async throws {
        let counter = CallCounter()
        let model = CountingModel(parts: [.textDelta("partial")], counter: counter, fails: true)
        let wrapped = wrapLanguageModel(model: model, middleware: [.cache()])
        let request = LanguageModelRequest(messages: [.user("x")])

        for _ in 0..<2 {
            do { _ = try await collect(wrapped.stream(request)); XCTFail("expected error") }
            catch { }
        }
        XCTAssertEqual(counter.count, 2)
    }

    func testCacheKeyStableAndModelScoped() {
        let request = LanguageModelRequest(messages: [.user("hello")])
        let a = MiddlewareCallContext(request: request, provider: "openai", modelID: "gpt-5")
        let b = MiddlewareCallContext(request: request, provider: "openai", modelID: "gpt-5")
        let otherModel = MiddlewareCallContext(request: request, provider: "openai", modelID: "gpt-4")
        let otherPrompt = MiddlewareCallContext(
            request: LanguageModelRequest(messages: [.user("world")]),
            provider: "openai", modelID: "gpt-5"
        )
        XCTAssertEqual(cacheKey(a), cacheKey(b))
        XCTAssertNotEqual(cacheKey(a), cacheKey(otherModel))
        XCTAssertNotEqual(cacheKey(a), cacheKey(otherPrompt))
    }
}

private final class CallCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    func bump() { lock.lock(); value += 1; lock.unlock() }
    var count: Int { lock.lock(); defer { lock.unlock() }; return value }
}

private struct CountingModel: LanguageModel {
    let provider = "counting"
    let modelID = "counting-1"
    let parts: [StreamPart]
    let counter: CallCounter
    var fails = false

    func stream(_ request: LanguageModelRequest) async throws -> AsyncThrowingStream<StreamPart, Error> {
        counter.bump()
        let scripted = parts
        let shouldFail = fails
        return AsyncThrowingStream { continuation in
            for part in scripted { continuation.yield(part) }
            if shouldFail {
                continuation.finish(throwing: AIError.transport("boom"))
            } else {
                continuation.finish()
            }
        }
    }
}

private struct ScriptedModel: LanguageModel {
    let provider = "scripted"
    let modelID = "scripted-1"
    let parts: [StreamPart]
    private let log = RequestLog()

    actor RequestLog {
        var requests: [LanguageModelRequest] = []
        func append(_ request: LanguageModelRequest) { requests.append(request) }
    }

    func lastRequest() async -> LanguageModelRequest? { await log.requests.last }

    func stream(_ request: LanguageModelRequest) async throws -> AsyncThrowingStream<StreamPart, Error> {
        await log.append(request)
        let scripted = parts
        return AsyncThrowingStream { continuation in
            for part in scripted { continuation.yield(part) }
            continuation.finish()
        }
    }
}

private struct CountingEmbeddingModel: EmbeddingModel {
    let provider = "counting"
    let modelID = "counting-embed"
    private let log = CallLog()

    actor CallLog {
        var batchSizes: [Int] = []
        func append(_ size: Int) { batchSizes.append(size) }
    }

    func batchSizes() async -> [Int] { await log.batchSizes }

    func embed(_ texts: [String]) async throws -> EmbeddingResponse {
        await log.append(texts.count)
        return EmbeddingResponse(
            embeddings: texts.map { [Double($0.count)] },
            usage: Usage(inputTokens: texts.count, outputTokens: 0)
        )
    }
}

private func markerMiddleware(_ marker: String) -> LanguageModelMiddleware {
    LanguageModelMiddleware(
        transformRequest: { request in
            var request = request
            request.stopSequences.append(marker)
            return request
        },
        wrapStream: { inner in
            AsyncThrowingStream { continuation in
                let task = Task {
                    do {
                        for try await part in inner {
                            if case .textDelta(let t) = part {
                                continuation.yield(.textDelta(t + marker))
                            } else {
                                continuation.yield(part)
                            }
                        }
                        continuation.finish()
                    } catch {
                        continuation.finish(throwing: error)
                    }
                }
                continuation.onTermination = { _ in task.cancel() }
            }
        }
    )
}

private func collect(_ stream: AsyncThrowingStream<StreamPart, Error>) async throws -> [StreamPart] {
    var parts: [StreamPart] = []
    for try await part in stream { parts.append(part) }
    return parts
}

private func joinedText(_ parts: [StreamPart]) -> String {
    parts.compactMap { if case .textDelta(let t) = $0 { return t } else { return nil } }.joined()
}

private func joinedReasoning(_ parts: [StreamPart]) -> String {
    parts.compactMap { if case .reasoningDelta(let t) = $0 { return t } else { return nil } }.joined()
}
