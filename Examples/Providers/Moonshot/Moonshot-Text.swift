import AI

enum MoonshotExamples {
    static func textAndReasoning() async throws {
        let result = streamText(
            model: MoonshotModel("kimi-k2.7-code"),
            prompt: "Refactor a bubble sort into quicksort in Swift.",
            reasoning: .high
        )
        for try await part in result.fullStream {
            if case .reasoningDelta(let text) = part { print(text, terminator: "") }
            if case .textDelta(let text) = part { print(text, terminator: "") }
        }
    }
}
