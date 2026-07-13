import XCTest
@testable import AI

struct MockModel: LanguageModel {
    let provider = "mock"
    let modelID = "mock-1"
    let scripts: [[StreamPart]]
    let counter = Counter()

    final class Counter: @unchecked Sendable { var value = 0 }

    func stream(_ request: LanguageModelRequest) async throws -> AsyncThrowingStream<StreamPart, Error> {
        let step = counter.value
        counter.value += 1
        let parts = step < scripts.count ? scripts[step] : [.finish(reason: .stop, usage: .init())]
        return AsyncThrowingStream { continuation in
            for p in parts { continuation.yield(p) }
            continuation.finish()
        }
    }
}

final class AITests: XCTestCase {

    func testJSONValueRoundTrip() throws {
        let value: JSONValue = ["name": "Ada", "age": 36, "tags": ["a", "b"], "ok": true]
        let data = try JSONEncoder().encode(value)
        let decoded = try JSONDecoder().decode(JSONValue.self, from: data)
        XCTAssertEqual(decoded["name"]?.stringValue, "Ada")
        XCTAssertEqual(decoded["age"]?.intValue, 36)
        XCTAssertEqual(decoded["ok"]?.boolValue, true)
    }

    func testPlainTextGeneration() async throws {
        let model = MockModel(scripts: [[
            .textDelta("Hello, "), .textDelta("world!"),
            .finish(reason: .stop, usage: Usage(inputTokens: 5, outputTokens: 3))
        ]])
        let result = try await generateText(model: model, messages: [.user("hi")])
        XCTAssertEqual(result.text, "Hello, world!")
        XCTAssertEqual(result.stepCount, 1)
        XCTAssertEqual(result.usage.outputTokens, 3)
    }

    func testAgenticToolLoop() async throws {
        let model = MockModel(scripts: [
            [
                .toolCall(ToolCall(id: "t1", name: "weather", arguments: ["city": "Mumbai"])),
                .finish(reason: .toolCalls, usage: .init())
            ],
            [
                .textDelta("It's 31°C in Mumbai."),
                .finish(reason: .stop, usage: .init())
            ]
        ])

        let weather = Tool(
            name: "weather",
            description: "Current weather for a city",
            parameters: ["type": "object", "properties": ["city": ["type": "string"]]]
        ) { args in
            let city = args["city"]?.stringValue ?? "?"
            return ["tempC": 31, "city": .string(city)]
        }

        let result = try await generateText(
            model: model, messages: [.user("weather in Mumbai?")], tools: [weather]
        )
        XCTAssertEqual(result.stepCount, 2)
        XCTAssertEqual(result.toolCalls.first?.name, "weather")
        XCTAssertEqual(result.toolResults.first?.output["tempC"]?.intValue, 31)
        XCTAssertEqual(result.text, "It's 31°C in Mumbai.")
    }

    func testUnknownToolProducesErrorResult() async throws {
        let model = MockModel(scripts: [
            [.toolCall(ToolCall(id: "t1", name: "ghost", arguments: [:])),
             .finish(reason: .toolCalls, usage: .init())],
            [.textDelta("done"), .finish(reason: .stop, usage: .init())]
        ])
        let result = try await generateText(model: model, messages: [.user("x")], tools: [])
        XCTAssertTrue(result.toolResults.first?.isError ?? false)
    }
}
