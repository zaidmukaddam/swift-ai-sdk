import XCTest
@testable import AI

final class TransportTests: XCTestCase {

    private func weatherTool() -> Tool {
        Tool(
            name: "weather", description: "weather",
            parameters: ["type": "object", "properties": ["city": ["type": "string"]]]
        ) { args in
            ["tempC": 31, "city": args["city"] ?? .null]
        }
    }

    private func scriptedModel() -> MockModel {
        MockModel(scripts: [
            [
                .toolCallStart(id: "c1", name: "weather"),
                .toolArgumentsDelta(id: "c1", partialJSON: #"{"city":"Mumbai"}"#),
                .toolCall(ToolCall(id: "c1", name: "weather", arguments: ["city": "Mumbai"])),
                .finish(reason: .toolCalls, usage: .init())
            ],
            [
                .textDelta("It's 31°C."),
                .finish(reason: .stop, usage: .init())
            ]
        ])
    }

    func testLocalTransportEmitsProtocolCompliantChunkSequence() async throws {
        let transport = LocalChatTransport(
            model: scriptedModel(), tools: [weatherTool()]
        )
        var types: [String] = []
        let chunks = try await transport.sendMessages(
            ChatRequest(chatID: "chat1", messages: [.user("weather in Mumbai?")])
        )
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

    func testLocalTransportChunksReduceToFinalMessage() async throws {
        let transport = LocalChatTransport(model: scriptedModel(), tools: [weatherTool()])
        let chunks = try await transport.sendMessages(
            ChatRequest(chatID: "chat1", messages: [.user("weather?")])
        )
        var reducer = UIMessageReducer()
        for try await chunk in chunks { reducer.apply(chunk) }

        XCTAssertTrue(reducer.isFinished)
        XCTAssertEqual(reducer.finishReason, .stop)
        XCTAssertEqual(reducer.message.text, "It's 31°C.")

        let toolParts = reducer.message.parts.compactMap {
            if case .tool(let tool) = $0 { return tool } else { return nil }
        }
        XCTAssertEqual(toolParts.count, 1)
        XCTAssertEqual(toolParts[0].state, .outputAvailable)
        XCTAssertEqual(toolParts[0].output?["tempC"]?.intValue, 31)
    }

    func testStreamErrorsBecomeErrorChunksInBand() async throws {
        struct ExplodingModel: LanguageModel {
            let provider = "boom"; let modelID = "boom-1"
            func stream(_ request: LanguageModelRequest) async throws -> AsyncThrowingStream<StreamPart, Error> {
                AsyncThrowingStream { continuation in
                    continuation.yield(.textDelta("partial"))
                    continuation.finish(throwing: AIError.http(status: 500, body: "exploded"))
                }
            }
        }
        let transport = LocalChatTransport(model: ExplodingModel(), maxSteps: 1)
        let chunks = try await transport.sendMessages(
            ChatRequest(chatID: "c", messages: [.user("x")])
        )
        var reducer = UIMessageReducer()
        for try await chunk in chunks { reducer.apply(chunk) }
        XCTAssertNotNil(reducer.errorText)
        XCTAssertEqual(reducer.finishReason, .error)
        XCTAssertEqual(reducer.message.text, "partial")
    }

    func testConvertToModelMessagesRoundTrip() {
        let ui: [UIMessage] = [
            UIMessage(id: "s", role: .system, parts: [.text(TextUIPart(text: "Be terse."))]),
            .user("weather?"),
            UIMessage(id: "a", role: .assistant, parts: [
                .stepStart,
                .tool(ToolUIPart(
                    toolName: "weather", toolCallID: "c1", state: .outputAvailable,
                    input: ["city": "Mumbai"], output: ["tempC": 31]
                )),
                .stepStart,
                .text(TextUIPart(text: "31°C", state: .done)),
                .reasoning(ReasoningUIPart(text: "ui-only", state: .done))
            ])
        ]
        let model = convertToModelMessages(ui)

        XCTAssertEqual(model.map(\.role), [.system, .user, .assistant, .tool])
        let assistant = model[2]
        XCTAssertTrue(assistant.content.contains {
            if case .toolCall(let call) = $0 { return call.name == "weather" } else { return false }
        })
        XCTAssertEqual(assistant.text, "31°C")
        guard case .toolResult(let result) = model[3].content.first else {
            return XCTFail("expected tool result")
        }
        XCTAssertEqual(result.toolCallID, "c1")
        XCTAssertEqual(result.output["tempC"]?.intValue, 31)
    }

    func testRegenerateDropsMessagesFromTarget() async throws {
        let model = MockModel(scripts: [
            [.textDelta("take two"), .finish(reason: .stop, usage: .init())]
        ])
        let transport = LocalChatTransport(model: model)
        let messages: [UIMessage] = [
            .user("hi", id: "u1"),
            .assistant("take one", id: "a1")
        ]
        let chunks = try await transport.sendMessages(ChatRequest(
            chatID: "c", messages: messages, trigger: .regenerateMessage, messageID: "a1"
        ))
        var reducer = UIMessageReducer()
        for try await chunk in chunks { reducer.apply(chunk) }
        XCTAssertEqual(reducer.message.text, "take two")
    }
}

@MainActor
final class ChatSessionTests: XCTestCase {

    struct ScriptedTransport: ChatTransport {
        var chunks: [UIMessageChunk]
        func sendMessages(_ request: ChatRequest) async throws -> AsyncThrowingStream<UIMessageChunk, Error> {
            let script = chunks
            return AsyncThrowingStream { continuation in
                for chunk in script { continuation.yield(chunk) }
                continuation.finish()
            }
        }
    }

    func testSendStreamsAssistantMessageAndSettles() async throws {
        guard #available(macOS 14.0, iOS 17.0, *) else { throw XCTSkip("needs Observation") }

        let transport = ScriptedTransport(chunks: [
            .start(messageID: "srv-1"),
            .startStep,
            .textStart(id: "t"),
            .textDelta(id: "t", delta: "Hello "),
            .textDelta(id: "t", delta: "there"),
            .textEnd(id: "t"),
            .finishStep,
            .finish(finishReason: .stop)
        ])
        let chat = ChatSession(transport: transport)
        chat.send("hi")

        XCTAssertEqual(chat.messages.first?.role, .user)
        try await settle(chat)

        XCTAssertEqual(chat.status, .ready)
        XCTAssertEqual(chat.messages.count, 2)
        XCTAssertEqual(chat.messages.last?.id, "srv-1")
        XCTAssertEqual(chat.messages.last?.text, "Hello there")
    }

    func testErrorChunkSetsErrorStatus() async throws {
        guard #available(macOS 14.0, iOS 17.0, *) else { throw XCTSkip("needs Observation") }

        let chat = ChatSession(transport: ScriptedTransport(chunks: [
            .start(),
            .error(errorText: "quota exceeded")
        ]))
        chat.send("hi")
        try await settle(chat)
        XCTAssertEqual(chat.status, .error("quota exceeded"))
    }

    func testRegenerateRemovesLastAssistantMessage() async throws {
        guard #available(macOS 14.0, iOS 17.0, *) else { throw XCTSkip("needs Observation") }

        let transport = ScriptedTransport(chunks: [
            .start(),
            .textStart(id: "t"),
            .textDelta(id: "t", delta: "regenerated"),
            .textEnd(id: "t"),
            .finish(finishReason: .stop)
        ])
        let chat = ChatSession(transport: transport, messages: [
            .user("hi", id: "u1"), .assistant("old answer", id: "a1")
        ])
        chat.regenerate()
        try await settle(chat)

        XCTAssertEqual(chat.messages.count, 2)
        XCTAssertEqual(chat.messages.last?.text, "regenerated")
        XCTAssertFalse(chat.messages.contains { $0.id == "a1" })
    }

    @available(macOS 14.0, iOS 17.0, *)
    private func settle(_ chat: ChatSession, timeout: TimeInterval = 2) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while chat.isLoading {
            if Date() > deadline { throw XCTSkip("chat did not settle in time") }
            try await Task.sleep(nanoseconds: 5_000_000)
        }
    }
}
