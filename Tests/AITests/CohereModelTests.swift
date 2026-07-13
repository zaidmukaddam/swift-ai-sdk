import XCTest
@testable import AI

final class CohereModelTests: XCTestCase {

    private let model = CohereModel(
        "command-a-03-2025", apiKey: "k", headers: ["x-team": "ios"]
    )

    private func body(_ request: LanguageModelRequest) -> [String: JSONValue] {
        CohereModel.requestBody(for: request, modelID: "command-a-03-2025").objectValue ?? [:]
    }

    func testChatURLAndHeaders() throws {
        let urlRequest = try model.buildURLRequest(LanguageModelRequest(messages: [.user("Hi")]))
        XCTAssertEqual(urlRequest.url?.absoluteString, "https://api.cohere.com/v2/chat")
        XCTAssertEqual(urlRequest.httpMethod, "POST")
        XCTAssertEqual(urlRequest.value(forHTTPHeaderField: "Authorization"), "Bearer k")
        XCTAssertEqual(urlRequest.value(forHTTPHeaderField: "content-type"), "application/json")
        XCTAssertEqual(urlRequest.value(forHTTPHeaderField: "x-team"), "ios")
    }

    func testMessageMapping() {
        let request = LanguageModelRequest(messages: [
            .system("Be terse."),
            .user("Weather in Mumbai?"),
            Message(role: .assistant, content: [
                .text("Checking."),
                .toolCall(ToolCall(id: "c1", name: "weather", arguments: ["city": "Mumbai"]))
            ]),
            Message(role: .tool, content: [
                .toolResult(ToolResult(toolCallID: "c1", name: "weather", output: ["tempC": 31]))
            ]),
            .assistant("It is 31 C.")
        ])
        let messages = body(request)["messages"]?.arrayValue ?? []
        guard messages.count == 5 else {
            return XCTFail("expected 5 messages, got \(messages.count)")
        }

        XCTAssertEqual(messages[0]["role"], "system")
        XCTAssertEqual(messages[0]["content"], "Be terse.")
        XCTAssertEqual(messages[1]["role"], "user")
        XCTAssertEqual(messages[1]["content"], "Weather in Mumbai?")

        XCTAssertEqual(messages[2]["role"], "assistant")
        XCTAssertNil(messages[2]["content"])
        let call = messages[2]["tool_calls"]?.arrayValue?.first
        XCTAssertEqual(call?["id"], "c1")
        XCTAssertEqual(call?["type"], "function")
        XCTAssertEqual(call?["function"]?["name"], "weather")
        XCTAssertEqual(call?["function"]?["arguments"], "{\"city\":\"Mumbai\"}")

        XCTAssertEqual(messages[3]["role"], "tool")
        XCTAssertEqual(messages[3]["tool_call_id"], "c1")
        XCTAssertEqual(messages[3]["content"], "{\"tempC\":31}")

        XCTAssertEqual(messages[4]["role"], "assistant")
        XCTAssertEqual(messages[4]["content"], "It is 31 C.")
    }

    func testStringToolOutputStaysRaw() {
        let request = LanguageModelRequest(messages: [
            Message(role: .tool, content: [
                .toolResult(ToolResult(toolCallID: "c1", name: "weather", output: "31 C"))
            ])
        ])
        let messages = body(request)["messages"]?.arrayValue ?? []
        XCTAssertEqual(messages.first?["content"], "31 C")
    }

    func testToolMappingNestsUnderFunction() {
        let tool = Tool(
            name: "weather", description: "Get weather", parameters: ["type": "object"]
        ) { _ in "x" }
        let request = LanguageModelRequest(messages: [.user("x")], tools: [tool])
        let tools = body(request)["tools"]?.arrayValue
        XCTAssertEqual(tools?.count, 1)
        XCTAssertEqual(tools?.first?["type"], "function")
        XCTAssertEqual(tools?.first?["function"]?["name"], "weather")
        XCTAssertEqual(tools?.first?["function"]?["description"], "Get weather")
        XCTAssertEqual(tools?.first?["function"]?["parameters"]?["type"], "object")
    }

    func testSamplingKnobsUseCohereNames() {
        let request = LanguageModelRequest(
            messages: [.user("x")],
            maxOutputTokens: 512,
            temperature: 0.2,
            topP: 0.9,
            stopSequences: ["END"]
        )
        let body = body(request)
        XCTAssertEqual(body["model"], "command-a-03-2025")
        XCTAssertEqual(body["stream"], true)
        XCTAssertEqual(body["max_tokens"]?.intValue, 512)
        XCTAssertEqual(body["temperature"]?.doubleValue, 0.2)
        XCTAssertEqual(body["p"]?.doubleValue, 0.9)
        XCTAssertNil(body["top_p"])
        XCTAssertEqual(body["stop_sequences"], ["END"])
    }

    func testJSONResponseFormatPutsSchemaBesideType() {
        let request = LanguageModelRequest(
            messages: [.user("x")],
            responseFormat: .json(schema: [
                "type": "object",
                "properties": ["name": ["type": "string"]]
            ])
        )
        let format = body(request)["response_format"]
        XCTAssertEqual(format?["type"], "json_object")
        XCTAssertEqual(format?["json_schema"]?["type"], "object")
        XCTAssertEqual(format?["json_schema"]?["properties"]?["name"]?["type"], "string")
    }

    func testProviderOptionsMergeAtTopLevel() {
        let request = LanguageModelRequest(
            messages: [.user("x")],
            providerOptions: [
                "k": 40,
                "seed": 42,
                "thinking": ["type": "enabled", "token_budget": 2048]
            ]
        )
        let body = body(request)
        XCTAssertEqual(body["k"]?.intValue, 40)
        XCTAssertEqual(body["seed"]?.intValue, 42)
        XCTAssertEqual(body["thinking"]?["type"], "enabled")
        XCTAssertEqual(body["thinking"]?["token_budget"]?.intValue, 2048)
    }

    func testMapFinishReasonTable() {
        let cases: [(raw: String, expected: FinishReason)] = [
            ("COMPLETE", .stop),
            ("STOP_SEQUENCE", .stop),
            ("MAX_TOKENS", .length),
            ("ERROR", .error),
            ("TOOL_CALL", .toolCalls),
            ("SOMETHING_NEW", .other)
        ]
        for testCase in cases {
            XCTAssertEqual(
                CohereModel.mapFinishReason(testCase.raw),
                testCase.expected,
                "raw=\(testCase.raw)"
            )
        }
    }

    private func decodeStream(_ events: [String]) -> [StreamPart] {
        var decoder = CohereModel.StreamDecoder()
        var parts: [StreamPart] = []
        for event in events {
            parts += decoder.parts(forEventData: event)
        }
        parts.append(decoder.finishPart())
        return parts
    }

    func testStreamingTextAndThinkingDecode() {
        let parts = decodeStream([
            #"{"type":"message-start","id":"gen-1"}"#,
            #"{"type":"content-start","index":0,"delta":{"message":{"content":{"type":"thinking","thinking":""}}}}"#,
            #"{"type":"content-delta","index":0,"delta":{"message":{"content":{"thinking":"Considering."}}}}"#,
            #"{"type":"content-end","index":0}"#,
            #"{"type":"content-start","index":1,"delta":{"message":{"content":{"type":"text","text":""}}}}"#,
            #"{"type":"content-delta","index":1,"delta":{"message":{"content":{"text":"Hello"}}}}"#,
            #"{"type":"content-delta","index":1,"delta":{"message":{"content":{"text":" world"}}}}"#,
            #"{"type":"content-end","index":1}"#,
            #"{"type":"message-end","delta":{"finish_reason":"COMPLETE","usage":{"tokens":{"input_tokens":7,"output_tokens":12}}}}"#,
            "[DONE]"
        ])
        guard parts.count == 4 else {
            return XCTFail("expected 4 parts, got \(parts.count): \(parts)")
        }
        guard case .reasoningDelta(let thinking) = parts[0] else {
            return XCTFail("expected reasoningDelta, got \(parts[0])")
        }
        XCTAssertEqual(thinking, "Considering.")
        guard case .textDelta(let first) = parts[1], case .textDelta(let second) = parts[2] else {
            return XCTFail("expected two textDeltas, got \(parts[1]), \(parts[2])")
        }
        XCTAssertEqual(first + second, "Hello world")
        guard case .finish(let reason, let usage) = parts[3] else {
            return XCTFail("expected finish, got \(parts[3])")
        }
        XCTAssertEqual(reason, .stop)
        XCTAssertEqual(usage.inputTokens, 7)
        XCTAssertEqual(usage.outputTokens, 12)
    }

    func testStreamingToolCallDecode() {
        let parts = decodeStream([
            #"{"type":"message-start","id":"gen-2"}"#,
            #"{"type":"tool-plan-delta","delta":{"message":{"tool_plan":"I will check."}}}"#,
            #"{"type":"tool-call-start","delta":{"message":{"tool_calls":{"id":"c1","type":"function","function":{"name":"weather","arguments":"{\"ci"}}}}}"#,
            #"{"type":"tool-call-delta","delta":{"message":{"tool_calls":{"function":{"arguments":"ty\":\"Mumbai\"}"}}}}}"#,
            #"{"type":"tool-call-end"}"#,
            #"{"type":"message-end","delta":{"finish_reason":"TOOL_CALL","usage":{"tokens":{"input_tokens":9,"output_tokens":4}}}}"#
        ])
        guard parts.count == 5 else {
            return XCTFail("expected 5 parts, got \(parts.count): \(parts)")
        }
        guard case .toolCallStart(let id, let name) = parts[0] else {
            return XCTFail("expected toolCallStart, got \(parts[0])")
        }
        XCTAssertEqual(id, "c1")
        XCTAssertEqual(name, "weather")
        guard case .toolArgumentsDelta(_, let firstChunk) = parts[1],
              case .toolArgumentsDelta(_, let secondChunk) = parts[2] else {
            return XCTFail("expected two toolArgumentsDeltas, got \(parts[1]), \(parts[2])")
        }
        XCTAssertEqual(firstChunk + secondChunk, "{\"city\":\"Mumbai\"}")
        guard case .toolCall(let call) = parts[3] else {
            return XCTFail("expected toolCall, got \(parts[3])")
        }
        XCTAssertEqual(call.id, "c1")
        XCTAssertEqual(call.name, "weather")
        XCTAssertEqual(call.arguments["city"], "Mumbai")
        guard case .finish(let reason, let usage) = parts[4] else {
            return XCTFail("expected finish, got \(parts[4])")
        }
        XCTAssertEqual(reason, .toolCalls)
        XCTAssertEqual(usage.inputTokens, 9)
        XCTAssertEqual(usage.outputTokens, 4)
    }

    func testZeroArgToolCallNormalizesNullArguments() {
        let parts = decodeStream([
            #"{"type":"tool-call-start","delta":{"message":{"tool_calls":{"id":"c2","type":"function","function":{"name":"ping","arguments":"null"}}}}}"#,
            #"{"type":"tool-call-end"}"#
        ])
        guard parts.count == 4 else {
            return XCTFail("expected 4 parts, got \(parts.count): \(parts)")
        }
        guard case .toolCall(let call) = parts[2] else {
            return XCTFail("expected toolCall, got \(parts[2])")
        }
        XCTAssertEqual(call.arguments, .object([:]))
        guard case .finish(let reason, _) = parts[3] else {
            return XCTFail("expected finish, got \(parts[3])")
        }
        XCTAssertEqual(reason, .toolCalls)
    }

    func testCitationStartMapsToSource() {
        let parts = decodeStream([
            #"{"type":"citation-start","index":0,"delta":{"message":{"citations":{"start":0,"end":5,"text":"snip","sources":[{"type":"document","id":"doc-0","document":{"id":"doc-0","title":"Weather FAQ","url":"https://example.com/faq"}}]}}}}"#,
            #"{"type":"citation-end","index":0}"#
        ])
        guard case .source(let source) = parts.first else {
            return XCTFail("expected source, got \(String(describing: parts.first))")
        }
        XCTAssertEqual(source.id, "source-0")
        XCTAssertEqual(source.title, "Weather FAQ")
        XCTAssertEqual(source.url, "https://example.com/faq")
    }
}

final class CohereEmbeddingModelTests: XCTestCase {

    func testEmbedURLAndHeaders() throws {
        let model = CohereEmbeddingModel("embed-english-v3.0", apiKey: "k")
        let urlRequest = try model.buildURLRequest(["hello"])
        XCTAssertEqual(urlRequest.url?.absoluteString, "https://api.cohere.com/v2/embed")
        XCTAssertEqual(urlRequest.httpMethod, "POST")
        XCTAssertEqual(urlRequest.value(forHTTPHeaderField: "Authorization"), "Bearer k")
    }

    func testEmbedRequestBody() {
        let body = CohereEmbeddingModel.requestBody(
            texts: ["a", "b"],
            modelID: "embed-english-v3.0",
            inputType: .searchDocument,
            truncate: .end,
            outputDimension: 1024
        ).objectValue ?? [:]
        XCTAssertEqual(body["model"], "embed-english-v3.0")
        XCTAssertEqual(body["texts"], ["a", "b"])
        XCTAssertEqual(body["embedding_types"], ["float"])
        XCTAssertEqual(body["input_type"], "search_document")
        XCTAssertEqual(body["truncate"], "END")
        XCTAssertEqual(body["output_dimension"]?.intValue, 1024)
    }

    func testEmbedRequestBodyDefaultsAndOmissions() {
        let body = CohereEmbeddingModel.requestBody(
            texts: ["a"],
            modelID: "embed-english-v3.0",
            inputType: .searchQuery,
            truncate: nil,
            outputDimension: nil
        ).objectValue ?? [:]
        XCTAssertEqual(body["input_type"], "search_query")
        XCTAssertNil(body["truncate"])
        XCTAssertNil(body["output_dimension"])
    }

    func testParseResponseReadsFloatVectorsAndBilledUnits() throws {
        let data = Data(#"""
        {"id":"r1",
         "embeddings":{"float":[[0.1,0.2],[0.3,0.4]]},
         "meta":{"billed_units":{"input_tokens":3}}}
        """#.utf8)
        let response = try CohereEmbeddingModel.parseResponse(data)
        XCTAssertEqual(response.embeddings.count, 2)
        XCTAssertEqual(response.embeddings[0], [0.1, 0.2])
        XCTAssertEqual(response.embeddings[1], [0.3, 0.4])
        XCTAssertEqual(response.usage.inputTokens, 3)
        XCTAssertEqual(response.usage.outputTokens, 0)
    }

    func testParseResponseWithoutFloatVectorsThrows() {
        let data = Data(#"{"embeddings":{},"meta":{}}"#.utf8)
        XCTAssertThrowsError(try CohereEmbeddingModel.parseResponse(data))
    }
}
