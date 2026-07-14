import AI

#if canImport(FoundationModels)
@available(iOS 26.0, macOS 26.0, *)
extension AppleFoundationModelsExamples {
    static func toolsAndStructuredOutput() async throws {
        let model = FoundationModelsModel()

        _ = try await generateText(
            model: model,
            prompt: "Check the weather in Mumbai.",
            tools: [exampleWeatherTool()]
        )

        let result = try await generateObject(
            model: model,
            of: ExampleSummary.self,
            schema: exampleSummarySchema,
            prompt: "Summarize Swift concurrency."
        )
        print(result.object)
    }
}
#endif

