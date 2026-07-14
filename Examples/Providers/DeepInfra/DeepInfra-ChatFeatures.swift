import AI

extension DeepInfraExamples {
    static func toolsAndStructuredOutput() async throws {
        let model = DeepInfraModel("deepseek-ai/DeepSeek-V4-Pro")

        _ = try await generateText(
            model: model,
            prompt: "Check the weather in Paris.",
            tools: [exampleWeatherTool()]
        )

        let summary = try await generateObject(
            model: model,
            of: ExampleSummary.self,
            schema: exampleSummarySchema,
            prompt: "Summarize Swift memory ownership."
        )
        print(summary.object)
    }
}
