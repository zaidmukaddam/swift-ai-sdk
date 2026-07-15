import AI

extension XAIExamples {
    static func searchAndServerTools() async throws {
        let grounded = try await generateText(
            model: XaiModel("grok-4.5"),
            prompt: "What happened in AI this week?",
            tools: [
                XaiModel.Tools.webSearch(enableImageSearch: true),
                XaiModel.Tools.xSearch(allowedXHandles: ["xai"])
            ]
        )
        print(grounded.sources.map { $0.url })

        let tools = try await generateText(
            model: XaiModel("grok-4.5"),
            prompt: "Search x.ai and summarize the latest announcement.",
            tools: [
                XaiModel.Tools.webSearch(allowedDomains: ["x.ai"]),
                XaiModel.Tools.xSearch(allowedXHandles: ["xai"]),
                XaiModel.Tools.codeExecution()
            ]
        )
        print(tools.text)
    }

    static func multiAgentResearch() async throws {
        let result = streamText(
            model: XaiModel("grok-4.20-multi-agent"),
            prompt: "What shipped across the AI labs this week?",
            tools: [
                XaiModel.Tools.webSearch(name: "xai_web_search"),
                XaiModel.Tools.xSearch(name: "xai_x_search"),
                XaiModel.Tools.codeExecution(name: "xai_code_execution")
            ],
            activeTools: ["xai_web_search", "xai_x_search", "xai_code_execution"]
        )
        for try await text in result.textStream {
            print(text, terminator: "")
        }
    }

    static func serverToolCatalog() {
        let tools = [
            XaiModel.Tools.webSearch(),
            XaiModel.Tools.xSearch(),
            XaiModel.Tools.codeExecution(),
            XaiModel.Tools.fileSearch(vectorStoreIds: ["vs_example"]),
            XaiModel.Tools.mcpServer(serverUrl: "https://mcp.example.com"),
            XaiModel.Tools.viewImage(),
            XaiModel.Tools.viewXVideo()
        ]
        print(tools.map(\.name))
    }
}
