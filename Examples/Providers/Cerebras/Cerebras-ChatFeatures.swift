import AI

extension CerebrasExamples {
    static func toolsAndStructuredOutput() async throws {
        let model = CerebrasModel("gpt-oss-120b")

        _ = try await generateText(
            model: model,
            prompt: "What is the weather in London?",
            tools: [exampleWeatherTool()]
        )

        let summary = try await generateObject(
            model: model,
            of: ExampleSummary.self,
            schema: exampleSummarySchema,
            prompt: "Summarize protocol-oriented programming."
        )
        print(summary.object)
    }
}
