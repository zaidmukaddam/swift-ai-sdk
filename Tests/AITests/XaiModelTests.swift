import XCTest
@testable import AI

final class XaiModelTests: XCTestCase {

    private func body(_ request: LanguageModelRequest) -> [String: JSONValue] {
        XaiModel.responsesBody(for: request, modelID: "grok-4").objectValue ?? [:]
    }

    func testResponsesRequestTargetsResponsesPath() throws {
        let config = XaiModel.ResponsesConfig(
            apiKey: "k",
            baseURL: URL(string: "https://api.x.ai/v1")!,
            headers: ["x-team": "ios"],
            urlSession: .shared
        )
        let urlRequest = try XaiModel.buildResponsesRequest(
            config, modelID: "grok-4",
            request: LanguageModelRequest(messages: [.user("hi")])
        )
        XCTAssertEqual(urlRequest.url?.absoluteString, "https://api.x.ai/v1/responses")
        XCTAssertEqual(urlRequest.httpMethod, "POST")
        XCTAssertEqual(urlRequest.value(forHTTPHeaderField: "Authorization"), "Bearer k")
        XCTAssertEqual(urlRequest.value(forHTTPHeaderField: "x-team"), "ios")
    }

    func testInputItemMapping() {
        let messages: [Message] = [
            .system("Be terse."),
            .user("weather?"),
            Message(role: .assistant, content: [
                .text("Checking."),
                .toolCall(ToolCall(id: "c1", name: "weather", arguments: ["city": "Mumbai"]))
            ]),
            Message(role: .tool, content: [
                .toolResult(ToolResult(toolCallID: "c1", name: "weather", output: ["tempC": 31]))
            ])
        ]
        let items = XaiModel.inputItems(from: messages)
        XCTAssertEqual(items.count, 5)

        XCTAssertEqual(items[0]["role"], "system")
        XCTAssertEqual(items[0]["content"]?.arrayValue?.first?["type"], "input_text")
        XCTAssertEqual(items[1]["role"], "user")
        XCTAssertEqual(items[2]["role"], "assistant")
        XCTAssertEqual(items[2]["content"], "Checking.")

        XCTAssertEqual(items[3]["type"], "function_call")
        XCTAssertEqual(items[3]["call_id"], "c1")
        XCTAssertEqual(items[3]["name"], "weather")
        XCTAssertEqual(items[3]["status"], "completed")
        XCTAssertNotNil(items[3]["arguments"]?.stringValue)

        XCTAssertEqual(items[4]["type"], "function_call_output")
        XCTAssertEqual(items[4]["call_id"], "c1")
        XCTAssertNotNil(items[4]["output"]?.stringValue)
    }

    func testFunctionToolsAreFlatNotNested() {
        let tool = Tool(name: "weather", description: "w", parameters: ["type": "object"]) { _ in "x" }
        let request = LanguageModelRequest(messages: [.user("x")], tools: [tool])
        let tools = body(request)["tools"]?.arrayValue
        XCTAssertEqual(tools?.count, 1)
        XCTAssertEqual(tools?.first?["type"], "function")
        XCTAssertEqual(tools?.first?["name"], "weather")
        XCTAssertNotNil(tools?.first?["parameters"])
        XCTAssertNil(tools?.first?["function"])
    }

    func testJSONModeUsesTextFormat() {
        let request = LanguageModelRequest(
            messages: [.user("x")],
            responseFormat: .json(schema: ["type": "object"], name: "answer")
        )
        let format = body(request)["text"]?["format"]
        XCTAssertEqual(format?["type"], "json_schema")
        XCTAssertEqual(format?["name"], "answer")
        XCTAssertEqual(format?["strict"], true)
        XCTAssertNotNil(format?["schema"])
    }

    func testProviderOptionsToolsAppendToFunctionTools() {
        let tool = Tool(name: "weather", description: "w", parameters: ["type": "object"]) { _ in "x" }
        let request = LanguageModelRequest(
            messages: [.user("x")],
            tools: [tool],
            providerOptions: ["tools": [["type": "web_search"]]]
        )
        let tools = body(request)["tools"]?.arrayValue
        XCTAssertEqual(tools?.count, 2)
        XCTAssertEqual(tools?.last?["type"], "web_search")
    }

    func testStreamAndChatVariantsShareProviderName() {
        XCTAssertEqual(XaiModel("grok-4").provider, "xai")
        XCTAssertEqual(XaiModel("grok-4").modelID, "grok-4")
        let chat = XaiModel.chat("grok-3", apiKey: "k")
        XCTAssertEqual(chat.provider, "xai")
        XCTAssertEqual(chat.modelID, "grok-3")
    }

    func testServerToolNameMapping() {
        XCTAssertEqual(XaiModel.serverToolName(for: "web_search_call"), "web_search")
        XCTAssertEqual(XaiModel.serverToolName(for: "x_search_call"), "x_search")
        XCTAssertEqual(XaiModel.serverToolName(for: "code_interpreter_call"), "code_interpreter")
        XCTAssertEqual(XaiModel.serverToolName(for: "code_execution_call"), "code_execution")
        XCTAssertNil(XaiModel.serverToolName(for: "function_call"))
    }

    func testSearchPayloadPrefersActionObject() {
        let item: JSONValue = .object([
            "type": "web_search_call",
            "action": .object(["query": "swift concurrency", "type": "search"]),
            "input": .string("{\"query\":\"ignored\"}")
        ])
        let payload = XaiModel.mergeSearchCallPayload(item)
        XCTAssertEqual(payload["query"], "swift concurrency")
        XCTAssertEqual(payload["type"], "search")
    }

    func testSearchPayloadFallsBackToInputJSONString() {
        let item: JSONValue = .object([
            "type": "x_search_call",
            "action": .object([:]),
            "input": .string("{\"query\":\"grok\",\"x_handles\":[\"xai\"]}")
        ])
        let payload = XaiModel.mergeSearchCallPayload(item)
        XCTAssertEqual(payload["query"], "grok")
        XCTAssertEqual(payload["x_handles"]?.arrayValue?.first, "xai")
    }

    func testSearchPayloadEmptyWhenNothingUsable() {
        let item: JSONValue = .object(["type": "web_search_call", "input": .string("")])
        XCTAssertEqual(XaiModel.mergeSearchCallPayload(item), .object([:]))
    }

    func testCodeInterpreterResultJoinsLogsAndSurfacesError() {
        let item: JSONValue = .object([
            "type": "code_interpreter_call",
            "outputs": .array([
                .object(["type": "logs", "logs": .string("line 1")]),
                .object(["type": "image", "url": .string("http://x")]),
                .object(["type": "logs", "logs": .string("line 2")])
            ]),
            "error": .string("boom")
        ])
        let result = XaiModel.codeInterpreterResult(item)
        XCTAssertEqual(result["output"], .string("line 1\nline 2"))
        XCTAssertEqual(result["error"], .string("boom"))
    }

    func testServerToolPayloadForSearchMirrorsInputAndResult() {
        let item: JSONValue = .object([
            "action": .object(["query": "swift"])
        ])
        let (input, result) = XaiModel.serverToolPayload("web_search_call", item)
        XCTAssertEqual(input, result)
        XCTAssertEqual(input["query"], "swift")
    }

    func testServerToolPayloadForCodeCarriesCodeAndOutput() {
        let item: JSONValue = .object([
            "code": .string("print(1)"),
            "outputs": .array([.object(["type": "logs", "logs": .string("1")])])
        ])
        let (input, result) = XaiModel.serverToolPayload("code_interpreter_call", item)
        XCTAssertEqual(input["code"], .string("print(1)"))
        XCTAssertEqual(result["output"], .string("1"))
    }

    func testParseDeferredExtractsTextReasoningAndUsage() {
        let completion: JSONValue = .object([
            "choices": .array([.object([
                "message": .object([
                    "content": .string("hello"),
                    "reasoning_content": .string("thinking")
                ]),
                "finish_reason": .string("stop")
            ])]),
            "usage": .object([
                "prompt_tokens": .number(12),
                "completion_tokens": .number(7),
                "completion_tokens_details": .object(["reasoning_tokens": .number(3)])
            ])
        ])
        let result = XaiModel.parseDeferred(completion)
        XCTAssertEqual(result.text, "hello")
        XCTAssertEqual(result.reasoning, "thinking")
        XCTAssertEqual(result.finishReason, .stop)
        XCTAssertEqual(result.usage.inputTokens, 12)
        XCTAssertEqual(result.usage.outputTokens, 7)
        XCTAssertEqual(result.usage.reasoningTokens, 3)
    }

    func testMapChatFinishReasonTable() {
        XCTAssertEqual(XaiModel.mapChatFinishReason("stop"), .stop)
        XCTAssertEqual(XaiModel.mapChatFinishReason("length"), .length)
        XCTAssertEqual(XaiModel.mapChatFinishReason("tool_calls"), .toolCalls)
        XCTAssertEqual(XaiModel.mapChatFinishReason("content_filter"), .contentFilter)
        XCTAssertEqual(XaiModel.mapChatFinishReason(nil), .other)
    }

    func testXaiFileParsesMetadata() {
        let json: JSONValue = .object([
            "id": .string("file-123"),
            "filename": .string("doc.pdf"),
            "bytes": .number(2048),
            "created_at": .number(1_700_000_000),
            "public_url": .string("https://x.ai/f/doc.pdf")
        ])
        let file = XaiFile(json)
        XCTAssertEqual(file?.id, "file-123")
        XCTAssertEqual(file?.filename, "doc.pdf")
        XCTAssertEqual(file?.bytes, 2048)
        XCTAssertEqual(file?.publicURL, "https://x.ai/f/doc.pdf")
        XCTAssertNil(XaiFile(.object(["filename": .string("no-id.pdf")])))
    }
}
