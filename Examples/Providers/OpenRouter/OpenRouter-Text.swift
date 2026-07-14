import AI

enum OpenRouterExamples {
    static func text() async throws {
        let result = streamText(
            model: OpenRouterModel("anthropic/claude-sonnet-5"),
            prompt: "Explain Swift actors simply.",
            reasoning: .medium
        )
        for try await text in result.textStream {
            print(text, terminator: "")
        }
    }
}
