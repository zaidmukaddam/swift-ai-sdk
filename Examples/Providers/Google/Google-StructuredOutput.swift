import AI

extension GoogleExamples {
    static func structuredOutput() async throws {
        let result = try await generateObject(
            model: GoogleModel("gemini-3.5-flash"),
            of: ExampleSummary.self,
            schema: exampleSummarySchema,
            prompt: "Summarize Swift macros."
        )
        print(result.object)
    }
}

