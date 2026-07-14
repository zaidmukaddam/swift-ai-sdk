import AI

extension OpenAIExamples {
    static func functionAndServerTools() async throws {
        let functionResult = try await generateText(
            model: OpenAIModel("gpt-5.6-sol"),
            prompt: "What is the weather in Mumbai?",
            tools: [exampleWeatherTool()]
        )
        print(functionResult.text)

        let searchResult = try await generateText(
            model: OpenAIModel("gpt-5.6-sol"),
            prompt: "What happened in Swift this week?",
            tools: [
                OpenAIModel.Tools.webSearch(allowedDomains: ["swift.org"]),
                OpenAIModel.Tools.codeInterpreter()
            ]
        )
        print(searchResult.text)
        print(searchResult.sources.map(\.url))
    }

    static func serverToolCatalog() {
        let tools = [
            OpenAIModel.Tools.webSearch(),
            OpenAIModel.Tools.webSearchPreview(),
            OpenAIModel.Tools.fileSearch(vectorStoreIds: ["vs_example"]),
            OpenAIModel.Tools.codeInterpreter(fileIds: ["file_example"])
        ]
        print(tools.map(\.name))
    }
}
