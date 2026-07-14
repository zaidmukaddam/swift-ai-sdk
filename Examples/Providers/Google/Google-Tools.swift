import AI

extension GoogleExamples {
    static func functionAndGroundingTools() async throws {
        _ = try await generateText(
            model: GoogleModel("gemini-3.5-flash"),
            prompt: "What is the weather in Mumbai?",
            tools: [exampleWeatherTool()]
        )

        let result = try await generateText(
            model: GoogleModel("gemini-3.5-flash"),
            prompt: "Ground an explanation of the latest Swift release.",
            tools: [
                GoogleModel.Tools.googleSearch(),
                GoogleModel.Tools.urlContext(),
                GoogleModel.Tools.codeExecution()
            ]
        )
        print(result.text)
    }

    static func serverToolCatalog() {
        let tools = [
            GoogleModel.Tools.googleSearch(),
            GoogleModel.Tools.urlContext(),
            GoogleModel.Tools.codeExecution(),
            GoogleModel.Tools.enterpriseWebSearch(),
            GoogleModel.Tools.googleMaps(),
            GoogleModel.Tools.fileSearch(fileSearchStoreNames: ["fileSearchStores/example"])
        ]
        print(tools.map(\.name))
    }
}
