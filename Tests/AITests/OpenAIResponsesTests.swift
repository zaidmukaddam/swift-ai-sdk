import XCTest
@testable import AI

final class OpenAIResponsesTests: XCTestCase {

    private func body(
        _ request: LanguageModelRequest, modelID: String = "gpt-4o"
    ) -> [String: JSONValue] {
        OpenAIModel.responsesBody(for: request, modelID: modelID).objectValue ?? [:]
    }

    func testResponsesRequestTargetsResponsesPath() throws {
        let config = OpenAIModel.ResponsesConfig(
            apiKey: "k",
            baseURL: URL(string: "https://api.openai.com/v1")!,
            headers: ["x-team": "ios"],
            urlSession: .shared
        )
        let urlRequest = try OpenAIModel.buildResponsesRequest(
            config, modelID: "gpt-5.6-luna",
            request: LanguageModelRequest(messages: [.user("hi")])
        )
        XCTAssertEqual(urlRequest.url?.absoluteString, "https://api.openai.com/v1/responses")
        XCTAssertEqual(urlRequest.httpMethod, "POST")
        XCTAssertEqual(urlRequest.value(forHTTPHeaderField: "Authorization"), "Bearer k")
        XCTAssertEqual(urlRequest.value(forHTTPHeaderField: "x-team"), "ios")
    }

    func testOrganizationAndProjectRideDedicatedHeaders() {
        let merged = OpenAIModel.mergedHeaders(
            organization: "org-1", project: "proj-1", headers: ["x-team": "ios"]
        )
        XCTAssertEqual(merged["OpenAI-Organization"], "org-1")
        XCTAssertEqual(merged["OpenAI-Project"], "proj-1")
        XCTAssertEqual(merged["x-team"], "ios")

        let overridden = OpenAIModel.mergedHeaders(
            organization: "org-1", project: nil,
            headers: ["OpenAI-Organization": "org-2"]
        )
        XCTAssertEqual(overridden["OpenAI-Organization"], "org-2")
        XCTAssertNil(overridden["OpenAI-Project"])
    }

    func testInputItemMapping() {
        let messages: [Message] = [
            .system("Be terse."),
            .user("weather?"),
            Message(role: .assistant, content: [
                .text("Checking."),
                .toolCall(ToolCall(id: "call_1", name: "weather", arguments: ["city": "Mumbai"]))
            ]),
            Message(role: .tool, content: [
                .toolResult(ToolResult(toolCallID: "call_1", name: "weather", output: ["tempC": 31]))
            ])
        ]
        let items = OpenAIModel.inputItems(from: messages, systemRole: "system")
        XCTAssertEqual(items.count, 5)

        XCTAssertEqual(items[0]["role"], "system")
        XCTAssertEqual(items[0]["content"], "Be terse.")

        XCTAssertEqual(items[1]["role"], "user")
        XCTAssertEqual(items[1]["content"]?.arrayValue?.first?["type"], "input_text")
        XCTAssertEqual(items[1]["content"]?.arrayValue?.first?["text"], "weather?")

        XCTAssertEqual(items[2]["role"], "assistant")
        XCTAssertEqual(items[2]["content"]?.arrayValue?.first?["type"], "output_text")
        XCTAssertEqual(items[2]["content"]?.arrayValue?.first?["text"], "Checking.")

        XCTAssertEqual(items[3]["type"], "function_call")
        XCTAssertEqual(items[3]["call_id"], "call_1")
        XCTAssertEqual(items[3]["name"], "weather")
        XCTAssertNotNil(items[3]["arguments"]?.stringValue)
        XCTAssertNil(items[3]["id"])
        XCTAssertNil(items[3]["status"])

        XCTAssertEqual(items[4]["type"], "function_call_output")
        XCTAssertEqual(items[4]["call_id"], "call_1")
        XCTAssertNotNil(items[4]["output"]?.stringValue)
    }

    func testSystemMessagesUseDeveloperRoleForReasoningModels() {
        let request = LanguageModelRequest(messages: [.system("Be terse."), .user("hi")])
        for reasoningID in ["o1", "o3-mini", "o4-mini", "gpt-5.6-luna"] {
            let input = body(request, modelID: reasoningID)["input"]?.arrayValue
            XCTAssertEqual(input?.first?["role"], "developer", "for \(reasoningID)")
        }
        for plainID in ["gpt-4o", "gpt-5-chat-latest"] {
            let input = body(request, modelID: plainID)["input"]?.arrayValue
            XCTAssertEqual(input?.first?["role"], "system", "for \(plainID)")
        }
    }

    func testReasoningModelsDropTemperatureAndTopP() {
        let request = LanguageModelRequest(
            messages: [.user("hi")], temperature: 0.7, topP: 0.9
        )
        let reasoning = body(request, modelID: "o3")
        XCTAssertNil(reasoning["temperature"])
        XCTAssertNil(reasoning["top_p"])

        let plain = body(request, modelID: "gpt-4o")
        XCTAssertEqual(plain["temperature"], 0.7)
        XCTAssertEqual(plain["top_p"], 0.9)
    }

    func testGpt51PlusKeepsSamplingParametersWhenEffortIsNone() {
        let request = LanguageModelRequest(
            messages: [.user("hi")], temperature: 0.7,
            providerOptions: ["reasoning": ["effort": "none"]]
        )
        XCTAssertEqual(body(request, modelID: "gpt-5.6-luna")["temperature"], 0.7)
        XCTAssertNil(body(request, modelID: "gpt-5")["temperature"])
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

    func testFinishReasonMappingMatchesTheAISDK() {
        XCTAssertEqual(OpenAIModel.mapFinishReason(nil, hadFunctionCall: false), .stop)
        XCTAssertEqual(OpenAIModel.mapFinishReason(nil, hadFunctionCall: true), .toolCalls)
        XCTAssertEqual(OpenAIModel.mapFinishReason("max_output_tokens", hadFunctionCall: false), .length)
        XCTAssertEqual(OpenAIModel.mapFinishReason("content_filter", hadFunctionCall: false), .contentFilter)
        XCTAssertEqual(OpenAIModel.mapFinishReason("mystery", hadFunctionCall: false), .other)
        XCTAssertEqual(OpenAIModel.mapFinishReason("mystery", hadFunctionCall: true), .toolCalls)
    }

    func testResponsesAndChatVariantsShareProviderName() {
        XCTAssertEqual(OpenAIModel("gpt-5.6-luna").provider, "openai")
        XCTAssertEqual(OpenAIModel("gpt-5.6-luna").modelID, "gpt-5.6-luna")
        let chat = OpenAIModel.chat("gpt-4o", apiKey: "k")
        XCTAssertEqual(chat.provider, "openai")
        XCTAssertEqual(chat.modelID, "gpt-4o")
    }

    func testChatModelStillBuildsChatCompletionsURLs() {
        let chat = OpenAIChatModel("gpt-4o", apiKey: "k")
        XCTAssertEqual(chat.provider, "openai")
        XCTAssertEqual(
            chat.requestURL(path: "chat/completions").absoluteString,
            "https://api.openai.com/v1/chat/completions"
        )
    }
}
