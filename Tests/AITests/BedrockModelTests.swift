import XCTest
@testable import AI

final class BedrockModelTests: XCTestCase {

    private func body(_ request: LanguageModelRequest) -> [String: JSONValue] {
        BedrockModel.requestBody(for: request).objectValue ?? [:]
    }

    func testConverseStreamURLAndHeaders() throws {
        let model = BedrockModel(
            "anthropic.claude-sonnet-4-5-20250929-v1:0",
            apiKey: "k",
            region: "eu-central-1",
            headers: ["x-team": "ios"]
        )
        let urlRequest = try model.buildURLRequest(LanguageModelRequest(messages: [.user("Hi")]))
        XCTAssertEqual(
            urlRequest.url?.absoluteString,
            "https://bedrock-runtime.eu-central-1.amazonaws.com/model/anthropic.claude-sonnet-4-5-20250929-v1%3A0/converse-stream"
        )
        XCTAssertEqual(urlRequest.httpMethod, "POST")
        XCTAssertEqual(urlRequest.value(forHTTPHeaderField: "Authorization"), "Bearer k")
        XCTAssertEqual(urlRequest.value(forHTTPHeaderField: "content-type"), "application/json")
        XCTAssertEqual(urlRequest.value(forHTTPHeaderField: "x-team"), "ios")
    }

    func testDefaultRegionIsUsEast1() throws {
        let model = BedrockModel("amazon.nova-lite-v1:0", apiKey: "k")
        let urlRequest = try model.buildURLRequest(LanguageModelRequest(messages: [.user("Hi")]))
        XCTAssertEqual(urlRequest.url?.host, "bedrock-runtime.us-east-1.amazonaws.com")
    }

    func testModelIDPercentEncodingMatchesEncodeURIComponent() {
        XCTAssertEqual(
            BedrockModel.encodeModelID(
                "arn:aws:bedrock:us-east-1:123456789012:inference-profile/us.amazon.nova-pro-v1:0"
            ),
            "arn%3Aaws%3Abedrock%3Aus-east-1%3A123456789012%3Ainference-profile%2Fus.amazon.nova-pro-v1%3A0"
        )
        XCTAssertEqual(BedrockModel.encodeModelID("a-b_c.d!e~f*g'h(i)j"), "a-b_c.d!e~f*g'h(i)j")
    }

    func testConverseBodySystemMessagesAndTurnMerging() {
        let request = LanguageModelRequest(messages: [
            .system("Be terse."),
            .user("Weather in Mumbai?"),
            Message(role: .assistant, content: [
                .text("Checking."),
                .toolCall(ToolCall(id: "t1", name: "weather", arguments: ["city": "Mumbai"]))
            ]),
            Message(role: .tool, content: [
                .toolResult(ToolResult(toolCallID: "t1", name: "weather", output: ["tempC": 31]))
            ]),
            .user("Thanks, and Pune?")
        ])
        let body = body(request)

        XCTAssertEqual(body["system"]?.arrayValue?.first?["text"], "Be terse.")

        let messages = body["messages"]?.arrayValue ?? []
        guard messages.count == 3 else {
            return XCTFail("expected 3 turns, got \(messages.count)")
        }
        XCTAssertEqual(messages.map { $0["role"]?.stringValue }, ["user", "assistant", "user"])

        XCTAssertEqual(messages[0]["content"]?.arrayValue?.first?["text"], "Weather in Mumbai?")

        let assistant = messages[1]["content"]?.arrayValue ?? []
        XCTAssertEqual(assistant.first?["text"], "Checking.")
        let toolUse = assistant.last?["toolUse"]
        XCTAssertEqual(toolUse?["toolUseId"], "t1")
        XCTAssertEqual(toolUse?["name"], "weather")
        XCTAssertEqual(toolUse?["input"]?["city"], "Mumbai")

        let merged = messages[2]["content"]?.arrayValue ?? []
        guard merged.count == 2 else {
            return XCTFail("expected merged user turn with 2 blocks, got \(merged.count)")
        }
        let toolResult = merged[0]["toolResult"]
        XCTAssertEqual(toolResult?["toolUseId"], "t1")
        XCTAssertEqual(
            toolResult?["content"]?.arrayValue?.first?["text"],
            "{\"tempC\":31}"
        )
        XCTAssertEqual(merged[1]["text"], "Thanks, and Pune?")
    }

    func testNonObjectToolCallInputIsWrapped() {
        let request = LanguageModelRequest(messages: [
            Message(role: .assistant, content: [
                .toolCall(ToolCall(id: "t1", name: "echo", arguments: .string("plain")))
            ]),
            .user("ok")
        ])
        let messages = body(request)["messages"]?.arrayValue ?? []
        let input = messages.first?["content"]?.arrayValue?.first?["toolUse"]?["input"]
        XCTAssertEqual(input?["rawInvalidInput"], "plain")
    }

    func testTrailingAssistantTextIsTrimmed() {
        let request = LanguageModelRequest(messages: [
            .user("Complete this."),
            .assistant("The answer is:  \n")
        ])
        let messages = body(request)["messages"]?.arrayValue ?? []
        XCTAssertEqual(messages.last?["content"]?.arrayValue?.last?["text"], "The answer is:")
    }

    func testInferenceConfigMappingAndTemperatureClamp() {
        let request = LanguageModelRequest(
            messages: [.user("x")],
            maxOutputTokens: 512,
            temperature: 1.7,
            topP: 0.9,
            stopSequences: ["END"]
        )
        let config = body(request)["inferenceConfig"]
        XCTAssertEqual(config?["maxTokens"]?.intValue, 512)
        XCTAssertEqual(config?["temperature"]?.doubleValue, 1.0)
        XCTAssertEqual(config?["topP"]?.doubleValue, 0.9)
        XCTAssertEqual(config?["stopSequences"], ["END"])
    }

    func testToolConfigUsesToolSpecShape() {
        let tool = Tool(
            name: "weather",
            description: "Get weather",
            parameters: ["type": "object"]
        ) { _ in "x" }
        let request = LanguageModelRequest(messages: [.user("x")], tools: [tool])
        let toolConfig = body(request)["toolConfig"]

        let spec = toolConfig?["tools"]?.arrayValue?.first?["toolSpec"]
        XCTAssertEqual(spec?["name"], "weather")
        XCTAssertEqual(spec?["description"], "Get weather")
        XCTAssertEqual(spec?["inputSchema"]?["json"]?["type"], "object")
        XCTAssertNil(toolConfig?["toolChoice"])
    }

    func testJSONModeInjectsForcedJsonTool() {
        let request = LanguageModelRequest(
            messages: [.user("x")],
            responseFormat: .json(schema: [
                "type": "object",
                "properties": ["name": ["type": "string"]]
            ])
        )
        let toolConfig = body(request)["toolConfig"]

        let spec = toolConfig?["tools"]?.arrayValue?.first?["toolSpec"]
        XCTAssertEqual(spec?["name"], "json")
        XCTAssertEqual(spec?["description"], "Respond with a JSON object.")
        XCTAssertEqual(spec?["inputSchema"]?["json"]?["type"], "object")
        XCTAssertEqual(toolConfig?["toolChoice"], JSONValue.object(["any": .object([:])]))
    }

    func testProviderOptionsMergeAtTopLevel() {
        let request = LanguageModelRequest(
            messages: [.user("x")],
            providerOptions: [
                "guardrailConfig": ["guardrailIdentifier": "g1", "guardrailVersion": "1"],
                "additionalModelRequestFields": [
                    "thinking": ["type": "enabled", "budget_tokens": 1024]
                ]
            ]
        )
        let body = body(request)
        XCTAssertEqual(body["guardrailConfig"]?["guardrailIdentifier"], "g1")
        XCTAssertEqual(body["additionalModelRequestFields"]?["thinking"]?["type"], "enabled")
    }

    func testMapStopReasonTable() {
        let cases: [(raw: String?, jsonFromTool: Bool, expected: FinishReason)] = [
            ("end_turn", false, .stop),
            ("stop_sequence", false, .stop),
            ("max_tokens", false, .length),
            ("content_filtered", false, .contentFilter),
            ("guardrail_intervened", false, .contentFilter),
            ("tool_use", false, .toolCalls),
            ("tool_use", true, .stop),
            ("something_new", false, .other),
            (nil, false, .other)
        ]
        for testCase in cases {
            XCTAssertEqual(
                BedrockModel.mapStopReason(
                    testCase.raw, isJsonResponseFromTool: testCase.jsonFromTool
                ),
                testCase.expected,
                "raw=\(testCase.raw ?? "nil") jsonFromTool=\(testCase.jsonFromTool)"
            )
        }
    }

    private func encodeFrame(headers: [(name: String, value: String)], payload: Data) -> [UInt8] {
        var headerBytes: [UInt8] = []
        for header in headers {
            headerBytes.append(UInt8(header.name.utf8.count))
            headerBytes.append(contentsOf: Array(header.name.utf8))
            headerBytes.append(7)
            let value = Array(header.value.utf8)
            headerBytes.append(contentsOf: uint16BE(UInt16(value.count)))
            headerBytes.append(contentsOf: value)
        }
        var frame = uint32BE(UInt32(12 + headerBytes.count + payload.count + 4))
        frame += uint32BE(UInt32(headerBytes.count))
        frame += uint32BE(CRC32.checksum(frame))
        frame += headerBytes
        frame += payload
        frame += uint32BE(CRC32.checksum(frame))
        return frame
    }

    private func uint32BE(_ value: UInt32) -> [UInt8] {
        [
            UInt8(value >> 24 & 0xFF), UInt8(value >> 16 & 0xFF),
            UInt8(value >> 8 & 0xFF), UInt8(value & 0xFF)
        ]
    }

    private func uint16BE(_ value: UInt16) -> [UInt8] {
        [UInt8(value >> 8 & 0xFF), UInt8(value & 0xFF)]
    }

    func testCRC32MatchesKnownCheckValue() {
        XCTAssertEqual(CRC32.checksum(Array("123456789".utf8)), 0xCBF4_3926)
    }

    func testEventFrameRoundTripsThroughDecoder() throws {
        let payload = Data(#"{"contentBlockIndex":0,"delta":{"text":"Hello"},"p":"abcd"}"#.utf8)
        let frame = encodeFrame(
            headers: [
                (name: ":message-type", value: "event"),
                (name: ":event-type", value: "contentBlockDelta"),
                (name: ":content-type", value: "application/json")
            ],
            payload: payload
        )

        var decoder = AWSEventStreamDecoder()
        var messages: [AWSEventStreamMessage] = []
        for (offset, byte) in frame.enumerated() {
            if let message = try decoder.feed(byte) {
                XCTAssertEqual(offset, frame.count - 1, "message completed early")
                messages.append(message)
            }
        }
        guard messages.count == 1, let message = messages.first else {
            return XCTFail("expected exactly 1 message, got \(messages.count)")
        }
        XCTAssertEqual(message.headers[":message-type"], "event")
        XCTAssertEqual(message.headers[":event-type"], "contentBlockDelta")
        XCTAssertEqual(message.headers[":content-type"], "application/json")
        XCTAssertEqual(message.payload, payload)
    }

    func testTwoFramesInOneChunkDecodeSeparately() throws {
        let first = encodeFrame(
            headers: [(name: ":event-type", value: "messageStart")],
            payload: Data(#"{"role":"assistant"}"#.utf8)
        )
        let second = encodeFrame(
            headers: [(name: ":event-type", value: "messageStop")],
            payload: Data(#"{"stopReason":"end_turn"}"#.utf8)
        )
        var decoder = AWSEventStreamDecoder()
        let messages = try decoder.feed(first + second)
        XCTAssertEqual(messages.count, 2)
        XCTAssertEqual(messages.first?.headers[":event-type"], "messageStart")
        XCTAssertEqual(messages.last?.headers[":event-type"], "messageStop")
        XCTAssertEqual(messages.last?.payload, Data(#"{"stopReason":"end_turn"}"#.utf8))
    }

    func testCorruptedPayloadFailsMessageCRC() {
        var frame = encodeFrame(
            headers: [(name: ":event-type", value: "metadata")],
            payload: Data(#"{"usage":{}}"#.utf8)
        )
        frame[frame.count - 5] ^= 0xFF
        var decoder = AWSEventStreamDecoder()
        XCTAssertThrowsError(try decoder.feed(frame)) { error in
            guard case AWSEventStreamError.checksumMismatch = error else {
                return XCTFail("expected checksumMismatch, got \(error)")
            }
        }
    }

    func testFrameShorterThanMinimumThrows() {
        var decoder = AWSEventStreamDecoder()
        XCTAssertThrowsError(try decoder.feed([0, 0, 0, 8])) { error in
            guard case AWSEventStreamError.malformedFrame = error else {
                return XCTFail("expected malformedFrame, got \(error)")
            }
        }
    }
}
