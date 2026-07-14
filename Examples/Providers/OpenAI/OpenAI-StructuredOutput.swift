import AI

extension OpenAIExamples {
    static func structuredOutput() async throws {
        let result = try await generateObject(
            model: OpenAIModel("gpt-5.6-sol"),
            of: ExampleSummary.self,
            schema: exampleSummarySchema,
            prompt: "Summarize Swift structured concurrency."
        )
        print(result.object)
    }
}

