import AI

extension TogetherAIExamples {
    static func toolsAndStructuredOutput() async throws {
        let model = TogetherAIModel("Qwen/Qwen3.7-Max")

        let weather = try await generateText(
            model: model,
            prompt: "What is the weather in Mumbai?",
            tools: [exampleWeatherTool()]
        )
        print(weather.text)

        let summary = try await generateObject(
            model: model,
            of: ExampleSummary.self,
            schema: exampleSummarySchema,
            prompt: "Summarize Swift structured concurrency."
        )
        print(summary.object)
    }
}
