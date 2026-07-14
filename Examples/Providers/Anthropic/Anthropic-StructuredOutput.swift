import AI

extension AnthropicExamples {
    static func structuredOutput() async throws {
        let result = try await generateObject(
            model: AnthropicModel("claude-sonnet-5"),
            of: ExampleSummary.self,
            schema: exampleSummarySchema,
            prompt: "Summarize protocol-oriented programming."
        )
        print(result.object)
    }
}

