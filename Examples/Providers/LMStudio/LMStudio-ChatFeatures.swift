import AI

extension LMStudioExamples {
    static func toolsAndStructuredOutput() async throws {
        let model = LMStudioModel("openai/gpt-oss-20b")

        _ = try await generateText(
            model: model,
            prompt: "Check the weather in Berlin.",
            tools: [exampleWeatherTool()]
        )

        let summary = try await generateObject(
            model: model,
            of: ExampleSummary.self,
            schema: exampleSummarySchema,
            prompt: "Summarize Swift generics."
        )
        print(summary.object)
    }
}
