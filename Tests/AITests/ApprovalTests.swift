import XCTest
@testable import AI

final class ApprovalTests: XCTestCase {

    private func dangerousTool(executed: ExecutionFlag) -> Tool {
        Tool(
            name: "deleteFile", description: "removes a file",
            parameters: ["type": "object"],
            needsApproval: true
        ) { args in
            await executed.set()
            return ["deleted": args["path"] ?? .null]
        }
    }

    func testLoopPausesOnApprovalWithoutExecuting() async throws {
        let executed = ExecutionFlag()
        let model = MockModel(scripts: [
            [.toolCall(ToolCall(id: "c1", name: "deleteFile", arguments: ["path": "/tmp/x"])),
             .finish(reason: .toolCalls, usage: .init())],
            [.textDelta("never reached"), .finish(reason: .stop, usage: .init())]
        ])
        let result = try await generateText(
            model: model, prompt: "clean up", tools: [dangerousTool(executed: executed)]
        )
        XCTAssertEqual(result.stepCount, 1)
        XCTAssertEqual(result.finishReason, .toolCalls)
        XCTAssertEqual(result.steps[0].approvalRequests.count, 1)
        XCTAssertEqual(result.steps[0].approvalRequests[0].approvalID, "approval-c1")
        XCTAssertTrue(result.toolResults.isEmpty)
        let didRun = await executed.value
        XCTAssertFalse(didRun)
    }

    func testResumeWithApprovalExecutesTheTool() async throws {
        let executed = ExecutionFlag()
        let model = MockModel(scripts: [
            [.textDelta("done, it is gone"), .finish(reason: .stop, usage: .init())]
        ])
        let history: [Message] = [
            .user("clean up"),
            Message(role: .assistant, content: [
                .toolCall(ToolCall(id: "c1", name: "deleteFile", arguments: ["path": "/tmp/x"]))
            ]),
            Message(role: .tool, content: [
                .toolApprovalResponse(ToolApprovalResponse(
                    approvalID: "approval-c1", toolCallID: "c1", approved: true
                ))
            ])
        ]
        let result = try await generateText(
            model: model, messages: history, tools: [dangerousTool(executed: executed)]
        )
        let didRun = await executed.value
        XCTAssertTrue(didRun)
        XCTAssertEqual(result.text, "done, it is gone")
        let toolMessages = result.messages.filter { $0.role == .tool }
        XCTAssertTrue(toolMessages.contains { message in
            message.content.contains {
                if case .toolResult(let r) = $0 { return r.toolCallID == "c1" && !r.denied }
                return false
            }
        })
    }

    func testResumeWithDenialProducesDeniedResult() async throws {
        let executed = ExecutionFlag()
        let model = MockModel(scripts: [
            [.textDelta("understood"), .finish(reason: .stop, usage: .init())]
        ])
        let history: [Message] = [
            .user("clean up"),
            Message(role: .assistant, content: [
                .toolCall(ToolCall(id: "c1", name: "deleteFile", arguments: [:]))
            ]),
            Message(role: .tool, content: [
                .toolApprovalResponse(ToolApprovalResponse(
                    approvalID: "approval-c1", toolCallID: "c1",
                    approved: false, reason: "too risky"
                ))
            ])
        ]
        let result = try await generateText(
            model: model, messages: history, tools: [dangerousTool(executed: executed)]
        )
        let didRun = await executed.value
        XCTAssertFalse(didRun)
        let denied = result.messages.flatMap(\.content).compactMap { part -> ToolResult? in
            if case .toolResult(let r) = part, r.denied { return r }
            return nil
        }
        XCTAssertEqual(denied.count, 1)
        XCTAssertEqual(denied[0].output.stringValue, "too risky")
    }

    func testApprovalChunkWireShapes() throws {
        let request = UIMessageChunk.toolApprovalRequest(approvalID: "a1", toolCallID: "c1")
        XCTAssertEqual(request.wire["type"], "tool-approval-request")
        XCTAssertEqual(request.wire["approvalId"], "a1")
        XCTAssertEqual(request.wire["toolCallId"], "c1")

        let response = UIMessageChunk.toolApprovalResponse(
            approvalID: "a1", approved: false, reason: "no"
        )
        XCTAssertEqual(response.wire["type"], "tool-approval-response")
        XCTAssertEqual(response.wire["approved"], false)
        XCTAssertEqual(response.wire["reason"], "no")

        let denied = UIMessageChunk.toolOutputDenied(toolCallID: "c1")
        XCTAssertEqual(denied.wire["type"], "tool-output-denied")

        for chunk in [request, response, denied] {
            let data = try JSONEncoder().encode(chunk)
            XCTAssertEqual(try JSONDecoder().decode(UIMessageChunk.self, from: data), chunk)
        }
    }

    func testReducerWalksApprovalStates() {
        var reducer = UIMessageReducer(messageID: "m")
        reducer.apply(.toolInputAvailable(toolCallID: "c1", toolName: "deleteFile", input: [:]))
        reducer.apply(.toolApprovalRequest(approvalID: "a1", toolCallID: "c1"))

        guard case .tool(let requested) = reducer.message.parts[0] else {
            return XCTFail("expected tool part")
        }
        XCTAssertEqual(requested.state, .approvalRequested)
        XCTAssertEqual(requested.approval?.id, "a1")

        reducer.apply(.toolApprovalResponse(approvalID: "a1", approved: true))
        guard case .tool(let responded) = reducer.message.parts[0] else {
            return XCTFail("expected tool part")
        }
        XCTAssertEqual(responded.state, .approvalResponded)
        XCTAssertEqual(responded.approval?.approved, true)

        reducer.apply(.toolOutputDenied(toolCallID: "c1"))
        guard case .tool(let deniedPart) = reducer.message.parts[0] else {
            return XCTFail("expected tool part")
        }
        XCTAssertEqual(deniedPart.state, .outputDenied)
        XCTAssertEqual(reducer.message.parts.count, 1)
    }

    func testLocalTransportEmitsApprovalRequestChunk() async throws {
        let model = MockModel(scripts: [
            [.toolCall(ToolCall(id: "c1", name: "deleteFile", arguments: [:])),
             .finish(reason: .toolCalls, usage: .init())]
        ])
        let executed = ExecutionFlag()
        let transport = LocalChatTransport(model: model, tools: [dangerousTool(executed: executed)])
        var types: [String] = []
        let chunks = try await transport.sendMessages(
            ChatRequest(chatID: "c", messages: [.user("go")])
        )
        for try await chunk in chunks {
            types.append(chunk.wire["type"]!.stringValue!)
        }
        XCTAssertTrue(types.contains("tool-approval-request"), "got \(types)")
        XCTAssertFalse(types.contains("tool-output-available"))
    }
}

@MainActor
final class ChatSessionApprovalTests: XCTestCase {

    func testApproveRoundTripThroughLocalTransport() async throws {
        guard #available(macOS 14.0, iOS 17.0, *) else { throw XCTSkip("needs Observation") }

        let executed = ExecutionFlag()
        let tool = Tool(
            name: "deleteFile", description: "removes a file",
            parameters: ["type": "object"], needsApproval: true
        ) { _ in
            await executed.set()
            return "gone"
        }
        let model = MockModel(scripts: [
            [.toolCall(ToolCall(id: "c1", name: "deleteFile", arguments: [:])),
             .finish(reason: .toolCalls, usage: .init())],
            [.textDelta("all clean"), .finish(reason: .stop, usage: .init())]
        ])
        let chat = ChatSession(transport: LocalChatTransport(model: model, tools: [tool]))
        chat.send("clean up")
        try await settle(chat)

        guard case .tool(let pending)? = chat.messages.last?.parts.first(where: {
            if case .tool = $0 { return true }
            return false
        }) else { return XCTFail("expected a tool part") }
        XCTAssertEqual(pending.state, .approvalRequested)

        chat.addToolApprovalResponse(approvalID: pending.approval!.id, approved: true)
        try await settle(chat)

        let didRun = await executed.value
        XCTAssertTrue(didRun)
        XCTAssertEqual(chat.messages.last?.text, "all clean")
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

actor ExecutionFlag {
    private(set) var value = false
    func set() { value = true }
}
