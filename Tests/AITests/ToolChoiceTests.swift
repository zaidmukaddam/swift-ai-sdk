import XCTest
@testable import AI

final class ToolChoiceTests: XCTestCase {

    private func tool(_ name: String) -> Tool {
        Tool(name: name, description: "d", parameters: ["type": "object"]) { _ in "ok" }
    }

    private func request(
        tools: [any AIToolProtocol], choice: ToolChoice
    ) -> LanguageModelRequest {
        LanguageModelRequest(messages: [.user("hi")], tools: tools, toolChoice: choice)
    }

    private func anthropicBody(_ choice: ToolChoice) -> [String: JSONValue] {
        AnthropicModel.requestBody(
            for: request(tools: [tool("weather"), tool("search")], choice: choice),
            modelID: "claude-test"
        ).objectValue ?? [:]
    }

    func testAnthropicAutoIsNotSerialized() {
        let body = anthropicBody(.auto)
        XCTAssertNil(body["tool_choice"])
        XCTAssertEqual(body["tools"]?.arrayValue?.count, 2)
    }

    func testAnthropicRequiredMapsToAny() {
        let body = anthropicBody(.required)
        XCTAssertEqual(body["tool_choice"], ["type": "any"])
        XCTAssertEqual(body["tools"]?.arrayValue?.count, 2)
    }

    func testAnthropicNamedTool() {
        let body = anthropicBody(.tool("weather"))
        XCTAssertEqual(body["tool_choice"], ["type": "tool", "name": "weather"])
    }

    func testAnthropicNoneOmitsToolsEntirely() {
        let body = anthropicBody(.none)
        XCTAssertNil(body["tools"])
        XCTAssertNil(body["tool_choice"])
    }

    func testAnthropicJSONModeOwnsToolChoice() {
        let request = LanguageModelRequest(
            messages: [.user("hi")],
            tools: [tool("weather")],
            toolChoice: .none,
            responseFormat: .json(schema: ["type": "object"], name: "answer")
        )
        let body = AnthropicModel.requestBody(for: request, modelID: "claude-test")
            .objectValue ?? [:]
        XCTAssertEqual(body["tool_choice"], ["type": "tool", "name": "answer"])
        XCTAssertEqual(body["tools"]?.arrayValue?.count, 2)
    }

    private func chatBody(_ choice: ToolChoice) -> [String: JSONValue] {
        OpenAIChatModel.requestBody(
            for: request(tools: [tool("weather"), tool("search")], choice: choice),
            modelID: "gpt-4o"
        ).objectValue ?? [:]
    }

    func testChatCompletionsToolChoiceStrings() {
        XCTAssertNil(chatBody(.auto)["tool_choice"])
        XCTAssertEqual(chatBody(.none)["tool_choice"], "none")
        XCTAssertEqual(chatBody(.required)["tool_choice"], "required")
    }

    func testChatCompletionsNamedToolNestsUnderFunction() {
        XCTAssertEqual(
            chatBody(.tool("weather"))["tool_choice"],
            ["type": "function", "function": ["name": "weather"]]
        )
    }

    func testChatCompletionsNoneKeepsTools() {
        XCTAssertEqual(chatBody(.none)["tools"]?.arrayValue?.count, 2)
    }

    private func openAIResponsesBody(_ choice: ToolChoice) -> [String: JSONValue] {
        OpenAIModel.responsesBody(
            for: request(tools: [tool("weather"), tool("search")], choice: choice),
            modelID: "gpt-5.6-luna"
        ).objectValue ?? [:]
    }

    func testOpenAIResponsesToolChoiceStrings() {
        XCTAssertNil(openAIResponsesBody(.auto)["tool_choice"])
        XCTAssertEqual(openAIResponsesBody(.none)["tool_choice"], "none")
        XCTAssertEqual(openAIResponsesBody(.required)["tool_choice"], "required")
    }

    func testOpenAIResponsesNamedToolIsFlat() {
        let choice = openAIResponsesBody(.tool("weather"))["tool_choice"]
        XCTAssertEqual(choice, ["type": "function", "name": "weather"])
        XCTAssertNil(choice?["function"])
    }

    private func xaiBody(_ choice: ToolChoice) -> [String: JSONValue] {
        XaiModel.responsesBody(
            for: request(tools: [tool("weather"), tool("search")], choice: choice),
            modelID: "grok-4"
        ).objectValue ?? [:]
    }

    func testXaiResponsesToolChoiceStrings() {
        XCTAssertNil(xaiBody(.auto)["tool_choice"])
        XCTAssertEqual(xaiBody(.none)["tool_choice"], "none")
        XCTAssertEqual(xaiBody(.required)["tool_choice"], "required")
    }

    func testXaiResponsesNamedToolIsFlat() {
        XCTAssertEqual(
            xaiBody(.tool("weather"))["tool_choice"],
            ["type": "function", "name": "weather"]
        )
    }

    private func googleBody(_ choice: ToolChoice) -> [String: JSONValue] {
        GoogleModel.requestBody(
            for: request(tools: [tool("weather"), tool("search")], choice: choice)
        ).objectValue ?? [:]
    }

    func testGoogleAutoSendsNoToolConfig() {
        let body = googleBody(.auto)
        XCTAssertNil(body["toolConfig"])
        XCTAssertNotNil(body["tools"])
    }

    func testGoogleNoneKeepsDeclarations() {
        let body = googleBody(.none)
        XCTAssertEqual(body["toolConfig"]?["functionCallingConfig"]?["mode"], "NONE")
        XCTAssertNotNil(body["tools"])
    }

    func testGoogleRequiredMapsToAny() {
        let config = googleBody(.required)["toolConfig"]?["functionCallingConfig"]
        XCTAssertEqual(config?["mode"], "ANY")
        XCTAssertNil(config?["allowedFunctionNames"])
    }

    func testGoogleNamedToolUsesAllowedFunctionNames() {
        let config = googleBody(.tool("weather"))["toolConfig"]?["functionCallingConfig"]
        XCTAssertEqual(config?["mode"], "ANY")
        XCTAssertEqual(config?["allowedFunctionNames"], ["weather"])
    }

    private func bedrockBody(_ choice: ToolChoice) -> [String: JSONValue] {
        BedrockModel.requestBody(
            for: request(tools: [tool("weather"), tool("search")], choice: choice)
        ).objectValue ?? [:]
    }

    func testBedrockAutoSendsToolsWithoutChoice() {
        let toolConfig = bedrockBody(.auto)["toolConfig"]
        XCTAssertEqual(toolConfig?["tools"]?.arrayValue?.count, 2)
        XCTAssertNil(toolConfig?["toolChoice"])
    }

    func testBedrockRequiredMapsToAny() {
        XCTAssertEqual(
            bedrockBody(.required)["toolConfig"]?["toolChoice"],
            ["any": [:]]
        )
    }

    func testBedrockNamedToolAlsoNarrowsTools() {
        let toolConfig = bedrockBody(.tool("weather"))["toolConfig"]
        XCTAssertEqual(toolConfig?["toolChoice"], ["tool": ["name": "weather"]])
        let tools = toolConfig?["tools"]?.arrayValue
        XCTAssertEqual(tools?.count, 1)
        XCTAssertEqual(tools?.first?["toolSpec"]?["name"], "weather")
    }

    func testBedrockNoneDropsToolConfig() {
        XCTAssertNil(bedrockBody(.none)["toolConfig"])
    }

    private func cohereBody(_ choice: ToolChoice) -> [String: JSONValue] {
        CohereModel.requestBody(
            for: request(tools: [tool("weather"), tool("search")], choice: choice),
            modelID: "command-a-03-2025"
        ).objectValue ?? [:]
    }

    func testCohereToolChoiceStrings() {
        XCTAssertNil(cohereBody(.auto)["tool_choice"])
        XCTAssertEqual(cohereBody(.none)["tool_choice"], "NONE")
        XCTAssertEqual(cohereBody(.required)["tool_choice"], "REQUIRED")
    }

    func testCohereNamedToolIsRequiredPlusNarrowedTools() {
        let body = cohereBody(.tool("weather"))
        XCTAssertEqual(body["tool_choice"], "REQUIRED")
        let tools = body["tools"]?.arrayValue
        XCTAssertEqual(tools?.count, 1)
        XCTAssertEqual(tools?.first?["function"]?["name"], "weather")
    }

    func testActiveToolsHidesToolFromRequestButExecutorStillRuns() async throws {
        let model = RecordingModel(scripts: [
            [
                .toolCall(ToolCall(id: "c1", name: "secret", arguments: [:])),
                .finish(reason: .toolCalls, usage: .init())
            ],
            [.textDelta("done"), .finish(reason: .stop, usage: .init())]
        ])
        let visible = Tool(name: "visible", description: "v", parameters: ["type": "object"]) { _ in "v" }
        let secret = Tool(name: "secret", description: "s", parameters: ["type": "object"]) { _ in "classified" }

        let result = try await generateText(
            model: model,
            prompt: "go",
            tools: [visible, secret],
            activeTools: ["visible"]
        )

        let requests = await model.requests()
        XCTAssertEqual(requests.count, 2)
        XCTAssertEqual(requests[0].tools.map(\.name), ["visible"])
        XCTAssertEqual(requests[1].tools.map(\.name), ["visible"])
        XCTAssertEqual(result.toolResults.count, 1)
        XCTAssertEqual(result.toolResults.first?.name, "secret")
        XCTAssertEqual(result.toolResults.first?.isError, false)
        XCTAssertEqual(result.toolResults.first?.output, "classified")
        XCTAssertEqual(result.text, "done")
    }

    func testStreamTextAppliesActiveTools() async throws {
        let model = RecordingModel(scripts: [
            [.textDelta("ok"), .finish(reason: .stop, usage: .init())]
        ])
        let result = streamText(
            model: model,
            prompt: "go",
            tools: [tool("a"), tool("b")],
            activeTools: ["b"]
        )
        for try await _ in result.fullStream {}
        let requests = await model.requests()
        XCTAssertEqual(requests.first?.tools.map(\.name), ["b"])
    }

    func testToolChoiceReachesTheRequest() async throws {
        let model = RecordingModel(scripts: [
            [.textDelta("hi"), .finish(reason: .stop, usage: .init())]
        ])
        _ = try await generateText(
            model: model,
            prompt: "go",
            tools: [tool("weather")],
            toolChoice: .tool("weather")
        )
        let requests = await model.requests()
        XCTAssertEqual(requests.first?.toolChoice, .tool("weather"))
    }

    func testAgentForwardsToolChoiceAndActiveTools() async throws {
        let model = RecordingModel(scripts: [
            [.textDelta("ok"), .finish(reason: .stop, usage: .init())]
        ])
        let agent = Agent(
            model: model,
            tools: [tool("visible"), tool("hidden")],
            toolChoice: .required,
            activeTools: ["visible"]
        )
        _ = try await agent.generate(prompt: "go")
        let request = await model.requests().first
        XCTAssertEqual(request?.toolChoice, .required)
        XCTAssertEqual(request?.tools.map(\.name), ["visible"])
    }
}

private actor RequestLog {
    private(set) var requests: [LanguageModelRequest] = []

    func record(_ request: LanguageModelRequest) -> Int {
        requests.append(request)
        return requests.count - 1
    }
}

private struct RecordingModel: LanguageModel {
    let provider = "recording"
    let modelID = "recording-1"
    let scripts: [[StreamPart]]
    private let log = RequestLog()

    func requests() async -> [LanguageModelRequest] { await log.requests }

    func stream(
        _ request: LanguageModelRequest
    ) async throws -> AsyncThrowingStream<StreamPart, Error> {
        let step = await log.record(request)
        let parts = step < scripts.count ? scripts[step] : [.finish(reason: .stop, usage: .init())]
        return AsyncThrowingStream { continuation in
            for part in parts { continuation.yield(part) }
            continuation.finish()
        }
    }
}
