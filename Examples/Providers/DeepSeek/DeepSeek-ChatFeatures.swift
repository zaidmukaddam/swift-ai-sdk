import AI

extension DeepSeekExamples {
    static func toolsAndStructuredOutput() async throws {
        let model = DeepSeekModel("deepseek-chat")

        _ = try await generateText(
            model: model,
            prompt: "Check the weather in Seoul.",
            tools: [exampleWeatherTool()]
        )

        let summary = try await generateObject(
            model: model,
            of: ExampleSummary.self,
            schema: exampleSummarySchema,
            prompt: "Summarize actor reentrancy."
        )
        print(summary.object)
    }
}
