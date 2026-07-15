import XCTest
@testable import AI

final class MCPAndTelemetryTests: XCTestCase {

    func testSSEResponseExtractionMatchesRequestID() throws {
        let sse = """
        event: message
        data: {"jsonrpc":"2.0","id":1,"result":{"tools":[]}}

        data: {"jsonrpc":"2.0","id":2,"result":{"tools":[{"name":"search"}]}}

        """
        let response = try MCPHTTPTransport.responseFromSSE(Data(sse.utf8), id: 2)
        XCTAssertEqual(
            response["result"]?["tools"]?.arrayValue?.first?["name"], "search"
        )
        XCTAssertThrowsError(
            try MCPHTTPTransport.responseFromSSE(Data(sse.utf8), id: 9)
        )
    }

    func testSSEResponseHandlesCRLFLineEndings() throws {
        let sse = "event: message\r\ndata: {\"jsonrpc\":\"2.0\",\"id\":7,\"result\":{\"tools\":[{\"name\":\"search\"}]}}\r\n\r\n"
        let response = try MCPHTTPTransport.responseFromSSE(Data(sse.utf8), id: 7)
        XCTAssertEqual(
            response["result"]?["tools"]?.arrayValue?.first?["name"], "search"
        )
    }

    func testSSEResponseHandlesMultilineDataField() throws {
        let sse = "data: {\"jsonrpc\":\"2.0\",\"id\":3,\r\ndata: \"result\":{\"ok\":true}}\r\n\r\n"
        let response = try MCPHTTPTransport.responseFromSSE(Data(sse.utf8), id: 3)
        XCTAssertEqual(response["result"]?["ok"]?.boolValue, true)
    }

    func testMCPToolBridgesIntoToolProtocol() {
        let client = MCPClient(transport: MCPHTTPTransport(
            url: URL(string: "https://mcp.example.com/mcp")!
        ))
        let tool = MCPTool(
            name: "search",
            description: "Search the index",
            parameters: ["type": "object", "properties": ["q": ["type": "string"]]],
            client: client
        )
        XCTAssertEqual(tool.name, "search")
        XCTAssertTrue(tool.hasExecutor)
        XCTAssertEqual(tool.parameters["properties"]?["q"]?["type"], "string")
    }

    func testTelemetrySpanBracketsOperations() async throws {
        let collector = RecordingCollector()
        AITelemetry.collector = collector
        defer { AITelemetry.collector = nil }

        let model = MockModel(scripts: [[
            .textDelta("hi"),
            .finish(reason: .stop, usage: Usage(inputTokens: 3, outputTokens: 2))
        ]])
        _ = try await generateText(model: model, prompt: "x")

        let events = collector.snapshot()
        XCTAssertEqual(events.map(\.phase), [.start, .end])
        XCTAssertEqual(events[0].name, "ai.generateText")
        XCTAssertEqual(events[0].attributes["ai.model.provider"], "mock")
        XCTAssertEqual(events[1].attributes["ai.usage.outputTokens"]?.intValue, 2)
        XCTAssertEqual(events[1].attributes["ai.response.finishReason"], "stop")
    }

    func testTelemetryErrorPhaseOnFailure() async {
        let collector = RecordingCollector()
        AITelemetry.collector = collector
        defer { AITelemetry.collector = nil }

        struct Exploding: LanguageModel {
            let provider = "boom"; let modelID = "b"
            func stream(_ request: LanguageModelRequest) async throws -> AsyncThrowingStream<StreamPart, Error> {
                throw AIError.http(status: 401, body: "no")
            }
        }
        _ = try? await generateText(model: Exploding(), prompt: "x", maxRetries: 0)

        let events = collector.snapshot()
        XCTAssertEqual(events.last?.phase, .error)
        XCTAssertNotNil(events.last?.attributes["error"])
    }

    func testTelemetryDisabledByDefaultCostsNothing() async throws {
        AITelemetry.collector = nil
        let model = MockModel(scripts: [[
            .textDelta("ok"), .finish(reason: .stop, usage: .init())
        ]])
        let result = try await generateText(model: model, prompt: "x")
        XCTAssertEqual(result.text, "ok")
    }

    func testUploadedFileShape() {
        let file = UploadedFile(id: "file-1", filename: "report.pdf", sizeBytes: 1024)
        XCTAssertEqual(file.id, "file-1")
        XCTAssertEqual(file.sizeBytes, 1024)
    }
}

final class RecordingCollector: AITelemetryCollector, @unchecked Sendable {
    private let lock = NSLock()
    private var events: [AITelemetryEvent] = []

    func record(_ event: AITelemetryEvent) {
        lock.withLock { events.append(event) }
    }

    func snapshot() -> [AITelemetryEvent] {
        lock.withLock { events }
    }
}
