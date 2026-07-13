import XCTest
@testable import AI

final class WireFormatTests: XCTestCase {

    private func json(_ chunk: UIMessageChunk) -> [String: JSONValue] {
        chunk.wire.objectValue ?? [:]
    }

    private func decode(_ raw: String) -> UIMessageChunk? {
        let value = try! JSONDecoder().decode(JSONValue.self, from: Data(raw.utf8))
        return UIMessageChunk(wire: value)
    }

    func testTextChunksUseDeltaField() {
        XCTAssertEqual(json(.textStart(id: "t1"))["type"], "text-start")
        let delta = json(.textDelta(id: "t1", delta: "Hi"))
        XCTAssertEqual(delta["type"], "text-delta")
        XCTAssertEqual(delta["delta"], "Hi")
        XCTAssertEqual(delta["id"], "t1")
        XCTAssertEqual(json(.textEnd(id: "t1"))["type"], "text-end")
    }

    func testToolInputDeltaUsesInputTextDelta() {
        let chunk = json(.toolInputDelta(toolCallID: "call_1", inputTextDelta: "{\"ci"))
        XCTAssertEqual(chunk["type"], "tool-input-delta")
        XCTAssertEqual(chunk["toolCallId"], "call_1")
        XCTAssertEqual(chunk["inputTextDelta"], "{\"ci")
    }

    func testToolLifecycleChunks() {
        let start = json(.toolInputStart(toolCallID: "c1", toolName: "weather"))
        XCTAssertEqual(start["type"], "tool-input-start")
        XCTAssertEqual(start["toolName"], "weather")

        let available = json(.toolInputAvailable(
            toolCallID: "c1", toolName: "weather", input: ["city": "Mumbai"]
        ))
        XCTAssertEqual(available["type"], "tool-input-available")
        XCTAssertEqual(available["input"]?["city"], "Mumbai")

        let output = json(.toolOutputAvailable(toolCallID: "c1", output: ["tempC": 31]))
        XCTAssertEqual(output["type"], "tool-output-available")
        XCTAssertEqual(output["output"]?["tempC"]?.intValue, 31)

        let failure = json(.toolOutputError(toolCallID: "c1", errorText: "boom"))
        XCTAssertEqual(failure["type"], "tool-output-error")
        XCTAssertEqual(failure["errorText"], "boom")
    }

    func testFinishReasonIsHyphenatedOnTheWire() {
        XCTAssertEqual(json(.finish(finishReason: .toolCalls))["finishReason"], "tool-calls")
        XCTAssertEqual(json(.finish(finishReason: .contentFilter))["finishReason"], "content-filter")
        XCTAssertEqual(FinishReason(wireValue: "tool-calls"), .toolCalls)
        XCTAssertNil(FinishReason(wireValue: "toolCalls"))
    }

    func testStepAndLifecycleChunks() {
        XCTAssertEqual(json(.startStep), ["type": "start-step"])
        XCTAssertEqual(json(.finishStep), ["type": "finish-step"])
        XCTAssertEqual(json(.start(messageID: "m1"))["messageId"], "m1")
        XCTAssertEqual(json(.abort(reason: "user"))["reason"], "user")
    }

    func testDecodeRealProtocolPayloads() {
        XCTAssertEqual(
            decode(#"{"type":"text-delta","id":"txt-0","delta":"Hello"}"#),
            .textDelta(id: "txt-0", delta: "Hello")
        )
        XCTAssertEqual(
            decode(#"{"type":"tool-input-delta","toolCallId":"c1","inputTextDelta":"{\"a\":"}"#),
            .toolInputDelta(toolCallID: "c1", inputTextDelta: "{\"a\":")
        )
        XCTAssertEqual(
            decode(#"{"type":"finish","finishReason":"tool-calls"}"#),
            .finish(finishReason: .toolCalls)
        )
        XCTAssertEqual(
            decode(#"{"type":"data-weather","id":"w1","data":{"tempC":21}}"#),
            .data(name: "weather", id: "w1", data: ["tempC": 21])
        )
    }

    func testUnknownChunkTypesAreSkippedNotFatal() {
        XCTAssertNil(decode(#"{"type":"reasoning-file","url":"https://x","mediaType":"image/png"}"#))
        if case .skipped = HTTPChatTransport.decodeChunk(#"{"type":"custom","kind":"x.y"}"#) {} else {
            XCTFail("unknown chunk should be skipped")
        }
    }

    func testDoneSentinelIsNeverJSONDecoded() {
        if case .done = HTTPChatTransport.decodeChunk("[DONE]") {} else {
            XCTFail("[DONE] must terminate, not decode")
        }
    }

    func testChunkRoundTripThroughCodable() throws {
        let chunks: [UIMessageChunk] = [
            .start(messageID: "m1"),
            .startStep,
            .textStart(id: "t"),
            .textDelta(id: "t", delta: "hi"),
            .textEnd(id: "t"),
            .toolInputStart(toolCallID: "c", toolName: "w"),
            .toolInputAvailable(toolCallID: "c", toolName: "w", input: ["q": 1]),
            .toolOutputAvailable(toolCallID: "c", output: "ok"),
            .finishStep,
            .finish(finishReason: .stop)
        ]
        for chunk in chunks {
            let data = try JSONEncoder().encode(chunk)
            let back = try JSONDecoder().decode(UIMessageChunk.self, from: data)
            XCTAssertEqual(back, chunk)
        }
    }

    func testSSEParserSplitsEventsOnBlankLines() {
        var parser = SSEParser()
        XCTAssertNil(parser.feed("data: {\"type\":\"start\"}"))
        let first = parser.feed("")
        XCTAssertEqual(first?.data, "{\"type\":\"start\"}")
        XCTAssertNil(parser.feed(": heartbeat comment"))
        XCTAssertNil(parser.feed("data: [DONE]"))
        XCTAssertEqual(parser.feed("")?.data, "[DONE]")
    }

    func testEncodeSSEFrame() throws {
        let frame = try UIMessageStream.encodeSSE(.textEnd(id: "t"))
        XCTAssertTrue(frame.hasPrefix("data: {"))
        XCTAssertTrue(frame.hasSuffix("\n\n"))
        XCTAssertTrue(frame.contains("\"text-end\""))
        XCTAssertEqual(UIMessageStream.doneSSE, "data: [DONE]\n\n")
        XCTAssertEqual(UIMessageStream.headers["x-vercel-ai-ui-message-stream"], "v1")
    }

    func testUIMessageWireFormat() throws {
        let message = UIMessage(id: "m1", role: .assistant, parts: [
            .stepStart,
            .text(TextUIPart(text: "Checking...", state: .done)),
            .tool(ToolUIPart(
                toolName: "weather", toolCallID: "c1", state: .outputAvailable,
                input: ["city": "Mumbai"], output: ["tempC": 31]
            )),
            .data(DataUIPart(name: "notice", id: "n1", data: "hello"))
        ])

        let wire = message.wire
        let parts = wire["parts"]!.arrayValue!
        XCTAssertEqual(parts[0]["type"], "step-start")
        XCTAssertEqual(parts[1]["type"], "text")
        XCTAssertEqual(parts[2]["type"], "tool-weather")
        XCTAssertEqual(parts[2]["state"], "output-available")
        XCTAssertEqual(parts[2]["toolCallId"], "c1")
        XCTAssertEqual(parts[3]["type"], "data-notice")

        let data = try JSONEncoder().encode(message)
        let back = try JSONDecoder().decode(UIMessage.self, from: data)
        XCTAssertEqual(back, message)
    }

    func testDynamicToolPartSerialization() throws {
        let message = UIMessage(id: "m", role: .assistant, parts: [
            .tool(ToolUIPart(
                toolName: "mcp_search", toolCallID: "c9", state: .inputAvailable,
                input: ["q": "swift"], isDynamic: true
            ))
        ])
        let part = message.wire["parts"]!.arrayValue![0]
        XCTAssertEqual(part["type"], "dynamic-tool")
        XCTAssertEqual(part["toolName"], "mcp_search")

        let back = try JSONDecoder().decode(UIMessage.self, from: JSONEncoder().encode(message))
        XCTAssertEqual(back, message)
    }
}
