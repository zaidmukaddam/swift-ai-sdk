import XCTest
@testable import AI
import AITesting

private final class Counter: @unchecked Sendable {
    var count = 0
}

private final class CountingImageModel: ImageModel, @unchecked Sendable {
    let provider = "mock"
    let modelID = "mock"
    var calls = 0

    func generateImages(_ request: ImageModelRequest) async throws -> ImageModelResponse {
        calls += 1
        return ImageModelResponse(images: Array(repeating: Data([1]), count: request.n))
    }
}

final class CoreFeaturesTests: XCTestCase {

    func testSmoothStreamChunksByWord() async throws {
        let input = AsyncThrowingStream<String, Error> { c in
            c.yield("Hel"); c.yield("lo wor"); c.yield("ld!"); c.finish()
        }
        var chunks: [String] = []
        for try await chunk in smoothStream(input, chunking: .word, delay: nil) {
            chunks.append(chunk)
        }
        XCTAssertEqual(chunks, ["Hello ", "world!"])
    }

    func testSmoothStreamChunksByLine() async throws {
        let input = AsyncThrowingStream<String, Error> { c in
            c.yield("line one\nli"); c.yield("ne two\n"); c.finish()
        }
        var chunks: [String] = []
        for try await chunk in smoothStream(input, chunking: .line, delay: nil) {
            chunks.append(chunk)
        }
        XCTAssertEqual(chunks, ["line one\n", "line two\n"])
    }

    func testGenerateObjectArray() async throws {
        struct Item: Decodable, Sendable { let n: Int }
        let model = MockLanguageModel(parts: [
            .textDelta(#"{"elements":[{"n":1},{"n":2},{"n":3}]}"#),
            .finish(reason: .stop, usage: Usage())
        ])
        let result = try await generateObjectArray(
            model: model, of: Item.self,
            elementSchema: .object(["type": .string("object")]), prompt: "list"
        )
        XCTAssertEqual(result.object.map(\.n), [1, 2, 3])
    }

    func testExperimentalOutputParsesStructuredResult() async throws {
        let model = MockLanguageModel(parts: [
            .textDelta(#"{"city":"Paris"}"#),
            .finish(reason: .stop, usage: Usage())
        ])
        let result = try await generateText(
            model: model, prompt: "x", output: .object(["type": .string("object")])
        )
        XCTAssertEqual(result.experimentalOutput?["city"]?.stringValue, "Paris")
    }

    func testRepairToolCallRenamesUnknownTool() async throws {
        let tool = Tool(name: "real", description: "", parameters: .object([:])) { _ in .string("done") }
        let model = MockLanguageModel(responses: [
            [
                .toolCall(ToolCall(id: "1", name: "wrong", arguments: .object([:]))),
                .finish(reason: .toolCalls, usage: Usage())
            ],
            [.textDelta("ok"), .finish(reason: .stop, usage: Usage())]
        ])
        let result = try await generateText(
            model: model, prompt: "x", tools: [tool],
            repairToolCall: { call, _ in
                call.name == "wrong"
                    ? ToolCall(id: call.id, name: "real", arguments: call.arguments) : nil
            }
        )
        XCTAssertTrue(result.toolResults.contains { $0.output.stringValue == "done" })
    }

    func testToolModelOutputPopulatesContent() async throws {
        var tool = Tool(name: "shot", description: "", parameters: .object([:])) { _ in
            .object(["url": .string("img")])
        }
        tool.modelOutput = { _ in
            [.text("screenshot"), .image(ImageContent(url: URL(string: "https://ex.com/a.png")!))]
        }
        let model = MockLanguageModel(responses: [
            [
                .toolCall(ToolCall(id: "1", name: "shot", arguments: .object([:]))),
                .finish(reason: .toolCalls, usage: Usage())
            ],
            [.textDelta("ok"), .finish(reason: .stop, usage: Usage())]
        ])
        let result = try await generateText(model: model, prompt: "x", tools: [tool])
        XCTAssertEqual(result.toolResults.first?.content?.count, 2)
    }

    func testMaxImagesPerCallBatches() async throws {
        let model = CountingImageModel()
        let result = try await generateImage(model: model, prompt: "x", n: 5, maxImagesPerCall: 2)
        XCTAssertEqual(result.images.count, 5)
        XCTAssertEqual(model.calls, 3)
    }

    func testOnChunkFires() async throws {
        let model = MockLanguageModel(parts: [
            .textDelta("a"), .textDelta("b"), .finish(reason: .stop, usage: Usage())
        ])
        let counter = Counter()
        let result = streamText(model: model, prompt: "x", onChunk: { _ in counter.count += 1 })
        for try await _ in result.textStream {}
        XCTAssertGreaterThan(counter.count, 0)
    }
}
