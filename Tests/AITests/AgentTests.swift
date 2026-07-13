import XCTest
@testable import AI

private struct ScriptedModel: LanguageModel {
    let provider = "mock"
    let modelID = "agent-mock-1"
    let scripts: [[StreamPart]]
    let recorder = Recorder()

    final class Recorder: @unchecked Sendable {
        private let lock = NSLock()
        private var stored: [LanguageModelRequest] = []

        var requests: [LanguageModelRequest] {
            lock.lock(); defer { lock.unlock() }
            return stored
        }

        func record(_ request: LanguageModelRequest) -> Int {
            lock.lock(); defer { lock.unlock() }
            stored.append(request)
            return stored.count - 1
        }
    }

    func stream(_ request: LanguageModelRequest) async throws -> AsyncThrowingStream<StreamPart, Error> {
        let step = recorder.record(request)
        let parts = step < scripts.count ? scripts[step] : [.finish(reason: .stop, usage: .init())]
        return AsyncThrowingStream { continuation in
            for part in parts { continuation.yield(part) }
            continuation.finish()
        }
    }
}

final class AgentTests: XCTestCase {

    private func weatherTool() -> Tool {
        Tool(
            name: "weather", description: "weather",
            parameters: ["type": "object", "properties": ["city": ["type": "string"]]]
        ) { args in
            ["tempC": 31, "city": args["city"] ?? .null]
        }
    }

    private func weatherScripts() -> [[StreamPart]] {
        [
            [
                .toolCallStart(id: "c1", name: "weather"),
                .toolArgumentsDelta(id: "c1", partialJSON: #"{"city":"Mumbai"}"#),
                .toolCall(ToolCall(id: "c1", name: "weather", arguments: ["city": "Mumbai"])),
                .finish(reason: .toolCalls, usage: .init())
            ],
            [
                .textDelta("It's 31C in Mumbai."),
                .finish(reason: .stop, usage: .init())
            ]
        ]
    }

    func testGenerateRunsToolLoopWithAgentTools() async throws {
        let model = ScriptedModel(scripts: weatherScripts())
        let agent = Agent(model: model, tools: [weatherTool()])

        let result = try await agent.generate(prompt: "weather in Mumbai?")

        XCTAssertEqual(result.stepCount, 2)
        XCTAssertEqual(result.toolCalls.first?.name, "weather")
        XCTAssertEqual(result.toolResults.first?.output["tempC"]?.intValue, 31)
        XCTAssertEqual(result.text, "It's 31C in Mumbai.")
        XCTAssertEqual(result.finishReason, .stop)

        let requests = model.recorder.requests
        XCTAssertEqual(requests.count, 2)
        XCTAssertEqual(requests[1].messages.map(\.role), [.user, .assistant, .tool])
    }

    private func namedTool(_ name: String) -> Tool {
        Tool(name: name, description: name, parameters: ["type": "object"]) { _ in .null }
    }

    private func doneScript() -> [[StreamPart]] {
        [[.textDelta("ok"), .finish(reason: .stop, usage: .init())]]
    }

    func testApplyToolOrderListedFirstThenAlphabetical() {
        let tools = [namedTool("zebra"), namedTool("apple"), namedTool("mango")]
        let ordered = applyToolOrder(tools, order: ["mango", "apple"])
        XCTAssertEqual(ordered.map(\.name), ["mango", "apple", "zebra"])
    }

    func testApplyToolOrderIgnoresUnknownAndDedupes() {
        let tools = [namedTool("b"), namedTool("a"), namedTool("c")]
        let ordered = applyToolOrder(tools, order: ["b", "b", "missing"])
        XCTAssertEqual(ordered.map(\.name), ["b", "a", "c"])
    }

    func testApplyToolOrderNilKeepsOriginalOrder() {
        let tools = [namedTool("z"), namedTool("a")]
        XCTAssertEqual(applyToolOrder(tools, order: nil).map(\.name), ["z", "a"])
    }

    func testAgentToolOrderReordersRequestTools() async throws {
        let model = ScriptedModel(scripts: doneScript())
        let agent = Agent(
            model: model,
            tools: [namedTool("zebra"), namedTool("apple"), namedTool("mango")],
            toolOrder: ["mango", "apple"]
        )
        _ = try await agent.generate(prompt: "hi")
        let request = try XCTUnwrap(model.recorder.requests.first)
        XCTAssertEqual(request.tools.map(\.name), ["mango", "apple", "zebra"])
    }

    func testPrepareCallSwapsModelAndSettings() async throws {
        let original = ScriptedModel(scripts: doneScript())
        let replacement = ScriptedModel(scripts: doneScript())
        let agent = Agent(
            model: original,
            prepareCall: { _ in
                PrepareCallResult(model: replacement, temperature: 0.9)
            }
        )
        _ = try await agent.generate(prompt: "hi")

        XCTAssertTrue(original.recorder.requests.isEmpty)
        let request = try XCTUnwrap(replacement.recorder.requests.first)
        XCTAssertEqual(request.temperature, 0.9)
    }

    func testPrepareCallOverridesToolsAndMessages() async throws {
        let model = ScriptedModel(scripts: doneScript())
        let agent = Agent(
            model: model,
            tools: [namedTool("old")],
            prepareCall: { _ in
                PrepareCallResult(
                    messages: [.system("Injected."), .user("rewritten")],
                    tools: [Tool(name: "new", description: "new", parameters: ["type": "object"]) { _ in .null }]
                )
            }
        )
        _ = try await agent.generate(prompt: "original")

        let request = try XCTUnwrap(model.recorder.requests.first)
        XCTAssertEqual(request.tools.map(\.name), ["new"])
        XCTAssertEqual(request.messages.map(\.role), [.system, .user])
        XCTAssertEqual(request.messages.last?.text, "rewritten")
    }

    func testInstructionsBecomeSystemMessage() async throws {
        let model = ScriptedModel(scripts: [
            [.textDelta("ok"), .finish(reason: .stop, usage: .init())]
        ])
        let agent = Agent(model: model, instructions: "Be terse.")

        _ = try await agent.generate(prompt: "hi")

        let request = try XCTUnwrap(model.recorder.requests.first)
        XCTAssertEqual(request.messages.map(\.role), [.system, .user])
        XCTAssertEqual(request.messages.first?.text, "Be terse.")
        XCTAssertEqual(request.messages.last?.text, "hi")
    }

    func testGenerateWithMessagesKeepsInstructionsFirst() async throws {
        let model = ScriptedModel(scripts: [
            [.textDelta("ok"), .finish(reason: .stop, usage: .init())]
        ])
        let agent = Agent(model: model, instructions: "Be terse.")

        _ = try await agent.generate(messages: [.user("one"), .assistant("two"), .user("three")])

        let request = try XCTUnwrap(model.recorder.requests.first)
        XCTAssertEqual(request.messages.map(\.role), [.system, .user, .assistant, .user])
        XCTAssertEqual(request.messages.first?.text, "Be terse.")
    }

    func testAgentTransportEmitsProtocolCompliantChunkSequence() async throws {
        let agent = Agent(
            model: ScriptedModel(scripts: weatherScripts()), tools: [weatherTool()]
        )
        let chunks = try await agent.sendMessages(
            ChatRequest(chatID: "chat1", messages: [.user("weather in Mumbai?")])
        )
        var types: [String] = []
        for try await chunk in chunks {
            types.append(chunk.wire["type"]!.stringValue!)
        }
        XCTAssertEqual(types, [
            "start",
            "start-step",
            "tool-input-start", "tool-input-delta", "tool-input-available",
            "tool-output-available",
            "finish-step",
            "start-step",
            "text-start", "text-delta", "text-end",
            "finish-step",
            "finish"
        ])
    }

    func testAgentTransportChunksReduceToFinalMessage() async throws {
        let agent = Agent(
            model: ScriptedModel(scripts: weatherScripts()), tools: [weatherTool()]
        )
        let chunks = try await agent.sendMessages(
            ChatRequest(chatID: "chat1", messages: [.user("weather?")])
        )
        var reducer = UIMessageReducer()
        for try await chunk in chunks { reducer.apply(chunk) }

        XCTAssertTrue(reducer.isFinished)
        XCTAssertEqual(reducer.finishReason, .stop)
        XCTAssertEqual(reducer.message.text, "It's 31C in Mumbai.")

        let toolParts = reducer.message.parts.compactMap {
            if case .tool(let tool) = $0 { return tool } else { return nil }
        }
        XCTAssertEqual(toolParts.count, 1)
        XCTAssertEqual(toolParts[0].state, .outputAvailable)
        XCTAssertEqual(toolParts[0].output?["tempC"]?.intValue, 31)
    }

    func testRegenerateTriggerDropsAssistantMessage() async throws {
        let model = ScriptedModel(scripts: [
            [.textDelta("take two"), .finish(reason: .stop, usage: .init())]
        ])
        let agent = Agent(model: model, instructions: "Be terse.")
        let chunks = try await agent.sendMessages(ChatRequest(
            chatID: "c",
            messages: [.user("hi", id: "u1"), .assistant("take one", id: "a1")],
            trigger: .regenerateMessage,
            messageID: "a1"
        ))
        var reducer = UIMessageReducer()
        for try await chunk in chunks { reducer.apply(chunk) }
        XCTAssertEqual(reducer.message.text, "take two")

        let request = try XCTUnwrap(model.recorder.requests.first)
        XCTAssertEqual(request.messages.map(\.role), [.system, .user])
        XCTAssertEqual(request.messages.last?.text, "hi")
    }
}
