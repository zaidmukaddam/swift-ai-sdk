import AI

extension AnthropicExamples {
    static func functionAndServerTools() async throws {
        _ = try await generateText(
            model: AnthropicModel("claude-sonnet-5"),
            prompt: "What is the weather in Mumbai?",
            tools: [exampleWeatherTool()]
        )

        let result = try await generateText(
            model: AnthropicModel("claude-sonnet-5"),
            prompt: "Search swift.org and summarize the latest release.",
            tools: [
                AnthropicModel.Tools.webSearch(maxUses: 3, allowedDomains: ["swift.org"]),
                AnthropicModel.Tools.webFetch(allowedDomains: ["swift.org"]),
                AnthropicModel.Tools.codeExecution()
            ]
        )
        print(result.text)
    }

    static func serverToolCatalog() {
        let tools = [
            AnthropicModel.Tools.webSearch(),
            AnthropicModel.Tools.webFetch(),
            AnthropicModel.Tools.codeExecution(),
            AnthropicModel.Tools.bash(),
            AnthropicModel.Tools.textEditor(),
            AnthropicModel.Tools.computer(displayWidthPx: 1440, displayHeightPx: 900),
            AnthropicModel.Tools.memory()
        ]
        print(tools.map(\.name))
    }
}
