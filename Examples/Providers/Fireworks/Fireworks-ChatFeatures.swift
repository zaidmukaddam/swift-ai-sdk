import AI

extension FireworksExamples {
    static func toolsAndStructuredOutput() async throws {
        let model = FireworksModel("accounts/fireworks/models/glm-5p2")

        let weather = try await generateText(
            model: model,
            prompt: "Check the weather in Tokyo.",
            tools: [exampleWeatherTool()]
        )
        print(weather.text)

        let summary = try await generateObject(
            model: model,
            of: ExampleSummary.self,
            schema: exampleSummarySchema,
            prompt: "Summarize value semantics in Swift."
        )
        print(summary.object)
    }
}
