import AI

enum MistralExamples {
    static func textAndReasoning() async throws {
        let result = streamText(
            model: MistralModel("mistral-medium-3.5"),
            prompt: "Plan a migration to Swift concurrency.",
            reasoning: .high
        )
        for try await text in result.textStream {
            print(text, terminator: "")
        }
    }
}
