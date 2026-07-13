import XCTest
@testable import AI

final class ProviderToolsTests: XCTestCase {

    private func fnTool(_ name: String = "weather") -> Tool {
        Tool(name: name, description: "w", parameters: ["type": "object"]) { _ in "x" }
    }

    func testProviderDefinedToolHasNoExecutor() {
        let tool = XaiModel.Tools.webSearch()
        XCTAssertFalse(tool.hasExecutor)
        XCTAssertEqual(tool.provider, "xai")
        XCTAssertEqual(tool.id, "xai.web_search")
    }

    func testRequestSplitsFunctionAndProviderTools() {
        let request = LanguageModelRequest(
            messages: [.user("hi")],
            tools: [fnTool(), XaiModel.Tools.webSearch(), OpenAIModel.Tools.webSearch()]
        )
        XCTAssertEqual(request.functionTools.count, 1)
        XCTAssertEqual(request.providerToolEntries(for: "xai").count, 1)
        XCTAssertEqual(request.providerToolEntries(for: "openai").count, 1)
        XCTAssertEqual(request.providerToolEntries(for: "google").count, 0)
    }

    func testXaiSerializesProviderToolsFlatAlongsideFunctions() {
        let request = LanguageModelRequest(
            messages: [.user("hi")],
            tools: [
                fnTool(),
                XaiModel.Tools.webSearch(allowedDomains: ["x.ai"], excludedDomains: ["spam.com"]),
                XaiModel.Tools.xSearch(allowedXHandles: ["xai"], fromDate: "2025-01-01"),
                XaiModel.Tools.codeExecution()
            ]
        )
        let tools = XaiModel.responsesBody(for: request, modelID: "grok-4")["tools"]?.arrayValue
        XCTAssertEqual(tools?.count, 4)
        XCTAssertEqual(tools?[0]["type"], "function")
        XCTAssertEqual(tools?[0]["name"], "weather")

        let web = tools?.first { $0["type"] == "web_search" }
        XCTAssertEqual(web?["allowed_domains"]?.arrayValue?.first, "x.ai")
        XCTAssertEqual(web?["excluded_domains"]?.arrayValue?.first, "spam.com")

        let x = tools?.first { $0["type"] == "x_search" }
        XCTAssertEqual(x?["allowed_x_handles"]?.arrayValue?.first, "xai")
        XCTAssertEqual(x?["from_date"], "2025-01-01")

        XCTAssertNotNil(tools?.first { $0["type"] == "code_interpreter" })
    }

    func testXaiIgnoresOtherProvidersTools() {
        let request = LanguageModelRequest(
            messages: [.user("hi")],
            tools: [AnthropicModel.Tools.webSearch()]
        )
        XCTAssertNil(XaiModel.responsesBody(for: request, modelID: "grok-4")["tools"])
    }

    func testOpenAISerializesProviderTools() {
        let request = LanguageModelRequest(
            messages: [.user("hi")],
            tools: [
                OpenAIModel.Tools.webSearch(allowedDomains: ["openai.com"], searchContextSize: "high"),
                OpenAIModel.Tools.fileSearch(vectorStoreIds: ["vs_1"], maxNumResults: 5),
                OpenAIModel.Tools.codeInterpreter()
            ]
        )
        let tools = OpenAIModel.responsesBody(for: request, modelID: "gpt-5")["tools"]?.arrayValue
        XCTAssertEqual(tools?.count, 3)

        let web = tools?.first { $0["type"] == "web_search" }
        XCTAssertEqual(web?["search_context_size"], "high")
        XCTAssertEqual(web?["filters"]?["allowed_domains"]?.arrayValue?.first, "openai.com")

        let file = tools?.first { $0["type"] == "file_search" }
        XCTAssertEqual(file?["vector_store_ids"]?.arrayValue?.first, "vs_1")
        XCTAssertEqual(file?["max_num_results"]?.intValue, 5)

        let code = tools?.first { $0["type"] == "code_interpreter" }
        XCTAssertEqual(code?["container"]?["type"], "auto")
    }

    func testGoogleSerializesProviderToolsAsSiblingEntries() {
        let request = LanguageModelRequest(
            messages: [.user("hi")],
            tools: [fnTool(), GoogleModel.Tools.googleSearch(), GoogleModel.Tools.urlContext()]
        )
        let tools = GoogleModel.requestBody(for: request)["tools"]?.arrayValue
        XCTAssertEqual(tools?.count, 3)
        XCTAssertNotNil(tools?.first { $0["functionDeclarations"] != nil })
        XCTAssertNotNil(tools?.first { $0["googleSearch"] != nil })
        XCTAssertNotNil(tools?.first { $0["urlContext"] != nil })
    }

    func testGoogleProviderToolsWithoutFunctionTools() {
        let request = LanguageModelRequest(
            messages: [.user("hi")],
            tools: [GoogleModel.Tools.codeExecution()]
        )
        let tools = GoogleModel.requestBody(for: request)["tools"]?.arrayValue
        XCTAssertEqual(tools?.count, 1)
        XCTAssertNotNil(tools?.first?["codeExecution"])
        XCTAssertNil(tools?.first { $0["functionDeclarations"] != nil })
    }

    func testAnthropicSerializesProviderToolsAndComputesBetas() {
        let request = LanguageModelRequest(
            messages: [.user("hi")],
            tools: [
                fnTool(),
                AnthropicModel.Tools.webSearch(maxUses: 3),
                AnthropicModel.Tools.computer(displayWidthPx: 1024, displayHeightPx: 768)
            ]
        )
        let body = AnthropicModel.requestBody(for: request, modelID: "claude-test")
        let tools = body["tools"]?.arrayValue
        XCTAssertEqual(tools?.count, 3)

        let web = tools?.first { $0["type"] == "web_search_20250305" }
        XCTAssertEqual(web?["name"], "web_search")
        XCTAssertEqual(web?["max_uses"]?.intValue, 3)

        let computer = tools?.first { $0["type"] == "computer_20250124" }
        XCTAssertEqual(computer?["display_width_px"]?.intValue, 1024)

        let betas = AnthropicModel.betaFlags(for: request)
        XCTAssertEqual(betas, ["computer-use-2025-01-24"])
    }

    func testAnthropicTextEditorNameFollowsVersion() {
        XCTAssertEqual(AnthropicModel.Tools.textEditor(version: "text_editor_20250124").name, "str_replace_editor")
        XCTAssertEqual(AnthropicModel.Tools.textEditor(version: "text_editor_20250728").name, "str_replace_based_edit_tool")
    }

    func testAnthropicNoBetasWhenNoProviderTools() {
        let request = LanguageModelRequest(messages: [.user("hi")], tools: [fnTool()])
        XCTAssertTrue(AnthropicModel.betaFlags(for: request).isEmpty)
    }

    func testProviderToolInToolsArrayDoesNotBreakGeneration() async throws {
        let model = MockModel(scripts: [[
            .textDelta("done"),
            .finish(reason: .stop, usage: .init())
        ]])
        let result = try await generateText(
            model: model, prompt: "go", tools: [XaiModel.Tools.webSearch()]
        )
        XCTAssertEqual(result.text, "done")
        XCTAssertEqual(result.finishReason, .stop)
        XCTAssertTrue(result.toolResults.isEmpty)
    }
}
