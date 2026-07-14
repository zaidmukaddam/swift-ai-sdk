import AI

extension BasetenExamples {
    static func toolsAndStructuredOutput() async throws {
        let model = BasetenModel("deepseek-ai/DeepSeek-V4-Pro")

        _ = try await generateText(
            model: model,
            prompt: "Check the weather in Bengaluru.",
            tools: [exampleWeatherTool()]
        )

        let summary = try await generateObject(
            model: model,
            of: ExampleSummary.self,
            schema: exampleSummarySchema,
            prompt: "Summarize Swift task groups."
        )
        print(summary.object)
    }
}
