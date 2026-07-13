import XCTest
@testable import AI

final class ReducerTests: XCTestCase {

    func testTextLifecycle() {
        var reducer = UIMessageReducer(messageID: "m")
        reducer.apply(.start(messageID: "server-id"))
        reducer.apply(.textStart(id: "t1"))
        reducer.apply(.textDelta(id: "t1", delta: "Hel"))
        reducer.apply(.textDelta(id: "t1", delta: "lo"))

        XCTAssertEqual(reducer.message.id, "server-id")
        guard case .text(let streaming) = reducer.message.parts[0] else {
            return XCTFail("expected text part")
        }
        XCTAssertEqual(streaming.text, "Hello")
        XCTAssertEqual(streaming.state, .streaming)

        reducer.apply(.textEnd(id: "t1"))
        reducer.apply(.finish(finishReason: .stop))
        guard case .text(let done) = reducer.message.parts[0] else {
            return XCTFail("expected text part")
        }
        XCTAssertEqual(done.state, .done)
        XCTAssertTrue(reducer.isFinished)
        XCTAssertEqual(reducer.finishReason, .stop)
    }

    func testToolLifecycleUpsertsByToolCallId() {
        var reducer = UIMessageReducer(messageID: "m")
        reducer.apply(.toolInputStart(toolCallID: "c1", toolName: "weather"))
        reducer.apply(.toolInputDelta(toolCallID: "c1", inputTextDelta: #"{"city": "Mum"#))
        reducer.apply(.toolInputDelta(toolCallID: "c1", inputTextDelta: #"bai"}"#))
        reducer.apply(.toolInputAvailable(
            toolCallID: "c1", toolName: "weather", input: ["city": "Mumbai"]
        ))
        reducer.apply(.toolOutputAvailable(toolCallID: "c1", output: ["tempC": 31]))

        XCTAssertEqual(reducer.message.parts.count, 1)
        guard case .tool(let tool) = reducer.message.parts[0] else {
            return XCTFail("expected tool part")
        }
        XCTAssertEqual(tool.state, .outputAvailable)
        XCTAssertEqual(tool.input?["city"], "Mumbai")
        XCTAssertEqual(tool.output?["tempC"]?.intValue, 31)
    }

    func testStreamingToolInputIsParsedAsPartialJSON() {
        var reducer = UIMessageReducer(messageID: "m")
        reducer.apply(.toolInputStart(toolCallID: "c1", toolName: "weather"))
        reducer.apply(.toolInputDelta(toolCallID: "c1", inputTextDelta: #"{"city": "Mum"#))

        guard case .tool(let tool) = reducer.message.parts[0] else {
            return XCTFail("expected tool part")
        }
        XCTAssertEqual(tool.state, .inputStreaming)
        XCTAssertEqual(tool.input?["city"], "Mum")
    }

    func testToolErrorState() {
        var reducer = UIMessageReducer(messageID: "m")
        reducer.apply(.toolInputAvailable(toolCallID: "c1", toolName: "w", input: [:]))
        reducer.apply(.toolOutputError(toolCallID: "c1", errorText: "kaboom"))
        guard case .tool(let tool) = reducer.message.parts[0] else {
            return XCTFail("expected tool part")
        }
        XCTAssertEqual(tool.state, .outputError)
        XCTAssertEqual(tool.errorText, "kaboom")
    }

    func testDataPartsUpsertByIdAndAppendWithout() {
        var reducer = UIMessageReducer(messageID: "m")
        reducer.apply(.data(name: "weather", id: "w1", data: ["tempC": 20]))
        reducer.apply(.data(name: "weather", id: "w1", data: ["tempC": 25]))
        reducer.apply(.data(name: "weather", data: "extra"))
        reducer.apply(.data(name: "spinner", data: "hide", transient: true))

        XCTAssertEqual(reducer.message.parts.count, 2)
        guard case .data(let upserted) = reducer.message.parts[0] else {
            return XCTFail("expected data part")
        }
        XCTAssertEqual(upserted.data["tempC"]?.intValue, 25)
    }

    func testInterleavedTextAndReasoningKeyedById() {
        var reducer = UIMessageReducer(messageID: "m")
        reducer.apply(.reasoningStart(id: "r1"))
        reducer.apply(.textStart(id: "t1"))
        reducer.apply(.reasoningDelta(id: "r1", delta: "thinking"))
        reducer.apply(.textDelta(id: "t1", delta: "answer"))
        reducer.apply(.reasoningEnd(id: "r1"))

        guard case .reasoning(let reasoning) = reducer.message.parts[0],
              case .text(let text) = reducer.message.parts[1] else {
            return XCTFail("expected [reasoning, text]")
        }
        XCTAssertEqual(reasoning.text, "thinking")
        XCTAssertEqual(reasoning.state, .done)
        XCTAssertEqual(text.text, "answer")
    }

    func testErrorChunkSurfacesWithoutFinishing() {
        var reducer = UIMessageReducer(messageID: "m")
        reducer.apply(.error(errorText: "rate limited"))
        XCTAssertEqual(reducer.errorText, "rate limited")
        XCTAssertFalse(reducer.isFinished)
        reducer.apply(.abort())
        XCTAssertTrue(reducer.isFinished)
    }
}

final class PartialJSONTests: XCTestCase {

    func testCompleteJSONPassesThrough() {
        XCTAssertEqual(PartialJSON.parse(#"{"a": 1}"#), ["a": 1])
    }

    func testTruncatedString() {
        XCTAssertEqual(PartialJSON.parse(#"{"city": "Mum"#), ["city": "Mum"])
    }

    func testTruncatedAfterKey() {
        XCTAssertEqual(PartialJSON.parse(#"{"city":"#), ["city": .null])
    }

    func testTruncatedKeyword() {
        XCTAssertEqual(PartialJSON.parse(#"{"ok": tru"#), ["ok": true])
        XCTAssertEqual(PartialJSON.parse(#"{"v": nul"#), ["v": .null])
    }

    func testTruncatedArrayAndNumber() {
        XCTAssertEqual(PartialJSON.parse(#"{"xs": [1, 2, 3"#), ["xs": [1, 2, 3]])
        XCTAssertEqual(PartialJSON.parse(#"{"n": 12."#), ["n": 12])
    }

    func testDanglingComma() {
        XCTAssertEqual(PartialJSON.parse(#"{"a": 1,"#), ["a": 1])
    }

    func testMarkdownFencesAreStripped() {
        XCTAssertEqual(PartialJSON.parse("```json\n{\"a\": 1}\n```"), ["a": 1])
    }

    func testGarbageReturnsNil() {
        XCTAssertNil(PartialJSON.parse("not json at all"))
        XCTAssertNil(PartialJSON.parse(""))
    }
}
