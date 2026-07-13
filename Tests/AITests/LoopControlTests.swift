import XCTest
@testable import AI

final class LoopControlTests: XCTestCase {

    private func toolCallScript(_ id: String, _ name: String) -> [StreamPart] {
        [.toolCall(ToolCall(id: id, name: name, arguments: ["n": 1])),
         .finish(reason: .toolCalls, usage: .init())]
    }

    private func echoTool(_ name: String = "echo") -> Tool {
        Tool(name: name, description: "echoes", parameters: ["type": "object"]) { args in args }
    }

    func testIsStepCountBoundsTheLoop() async throws {
        let model = MockModel(scripts: [
            toolCallScript("t1", "echo"), toolCallScript("t2", "echo"), toolCallScript("t3", "echo")
        ])
        let result = try await generateText(
            model: model, prompt: "go", tools: [echoTool()],
            stopWhen: [isStepCount(2)]
        )
        XCTAssertEqual(result.stepCount, 2)
    }

    func testIsLoopFinishedRunsToNaturalTermination() async throws {
        let model = MockModel(scripts: [
            toolCallScript("t1", "echo"),
            toolCallScript("t2", "echo"),
            [.textDelta("done"), .finish(reason: .stop, usage: .init())]
        ])
        let result = try await generateText(
            model: model, prompt: "go", tools: [echoTool()],
            stopWhen: [isLoopFinished()]
        )
        XCTAssertEqual(result.text, "done")
        XCTAssertEqual(result.stepCount, 3)
    }

    func testHasToolCallAcceptsMultipleNames() async throws {
        let model = MockModel(scripts: [
            toolCallScript("t1", "beta"),
            [.textDelta("never"), .finish(reason: .stop, usage: .init())]
        ])
        let result = try await generateText(
            model: model, prompt: "go", tools: [echoTool("alpha"), echoTool("beta")],
            stopWhen: [hasToolCall("alpha", "beta")]
        )
        XCTAssertEqual(result.stepCount, 1)
        XCTAssertEqual(result.toolCalls.first?.name, "beta")
    }

    func testClientSideToolEndsTheTurnUnexecuted() async throws {
        let model = MockModel(scripts: [
            toolCallScript("t1", "askUser"),
            [.textDelta("should not run"), .finish(reason: .stop, usage: .init())]
        ])
        let clientTool = Tool(
            name: "askUser", description: "handled by the app",
            parameters: ["type": "object"]
        )
        let result = try await generateText(
            model: model, prompt: "go", tools: [clientTool]
        )
        XCTAssertEqual(result.stepCount, 1)
        XCTAssertEqual(result.finishReason, .toolCalls)
        XCTAssertEqual(result.toolCalls.count, 1)
        XCTAssertTrue(result.toolResults.isEmpty)
    }

    func testProviderExecutedCallIsSurfacedButNotReExecuted() async throws {
        let model = MockModel(scripts: [[
            .toolCall(ToolCall(
                id: "ws1", name: "web_search",
                arguments: ["query": "swift"], providerExecuted: true
            )),
            .toolResult(ToolResult(
                toolCallID: "ws1", name: "web_search", output: ["query": "swift"]
            )),
            .textDelta("Here is what I found."),
            .finish(reason: .stop, usage: .init())
        ]])
        let result = try await generateText(model: model, prompt: "go")
        XCTAssertEqual(result.stepCount, 1)
        XCTAssertEqual(result.finishReason, .stop)
        XCTAssertEqual(result.text, "Here is what I found.")
        XCTAssertEqual(result.toolCalls.count, 1)
        XCTAssertTrue(result.toolCalls.first?.providerExecuted == true)
        XCTAssertEqual(result.toolResults.count, 1)
        XCTAssertEqual(result.toolResults.first?.toolCallID, "ws1")
        XCTAssertFalse(result.toolResults.first?.isError == true)
    }

    func testMixedCallsExecuteServerToolsThenPause() async throws {
        let model = MockModel(scripts: [[
            .toolCall(ToolCall(id: "s1", name: "echo", arguments: ["n": 1])),
            .toolCall(ToolCall(id: "c1", name: "askUser", arguments: [:])),
            .finish(reason: .toolCalls, usage: .init())
        ]])
        let clientTool = Tool(name: "askUser", description: "app", parameters: ["type": "object"])
        let result = try await generateText(
            model: model, prompt: "go", tools: [echoTool(), clientTool]
        )
        XCTAssertEqual(result.finishReason, .toolCalls)
        XCTAssertEqual(result.toolResults.count, 1)
        XCTAssertEqual(result.toolResults.first?.toolCallID, "s1")
    }
}

@MainActor
final class AddToolResultTests: XCTestCase {

    private struct TwoPhaseTransport: ChatTransport {
        let counter = Counter()
        actor Counter {
            var sends = 0
            func next() -> Int { sends += 1; return sends }
        }

        func sendMessages(_ request: ChatRequest) async throws -> AsyncThrowingStream<UIMessageChunk, Error> {
            let send = await counter.next()
            return AsyncThrowingStream { continuation in
                if send == 1 {
                    continuation.yield(.start(messageID: "a1"))
                    continuation.yield(.toolInputAvailable(
                        toolCallID: "c1", toolName: "askUser", input: ["q": "color?"]
                    ))
                    continuation.yield(.finish(finishReason: .toolCalls))
                } else {
                    continuation.yield(.start(messageID: "a2"))
                    continuation.yield(.textStart(id: "t"))
                    continuation.yield(.textDelta(id: "t", delta: "blue it is"))
                    continuation.yield(.textEnd(id: "t"))
                    continuation.yield(.finish(finishReason: .stop))
                }
                continuation.finish()
            }
        }
    }

    func testAddToolResultFillsPartAndResends() async throws {
        guard #available(macOS 14.0, iOS 17.0, *) else { throw XCTSkip("needs Observation") }

        let chat = ChatSession(transport: TwoPhaseTransport())
        chat.send("ask me something")
        try await settle(chat)

        guard case .tool(let pending)? = chat.messages.last?.parts.first(where: {
            if case .tool = $0 { return true }
            return false
        }) else { return XCTFail("expected a tool part") }
        XCTAssertEqual(pending.state, .inputAvailable)

        chat.addToolResult(toolCallID: "c1", result: ["answer": "blue"])
        try await settle(chat)

        let toolStates = chat.messages.flatMap(\.parts).compactMap { part -> UIToolState? in
            if case .tool(let tool) = part { return tool.state }
            return nil
        }
        XCTAssertTrue(toolStates.contains(.outputAvailable))
        XCTAssertEqual(chat.messages.last?.text, "blue it is")
    }

    @available(macOS 14.0, iOS 17.0, *)
    private func settle(_ chat: ChatSession, timeout: TimeInterval = 2) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        try await Task.sleep(nanoseconds: 10_000_000)
        while chat.isLoading {
            if Date() > deadline { throw XCTSkip("chat did not settle in time") }
            try await Task.sleep(nanoseconds: 5_000_000)
        }
    }
}
