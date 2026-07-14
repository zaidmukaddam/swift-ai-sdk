import AI

enum GroqExamples {
    static func textAndReasoning() async throws {
        let result = streamText(
            model: GroqModel("openai/gpt-oss-120b"),
            prompt: "Explain actor isolation.",
            reasoning: .high
        )
        for try await part in result.fullStream {
            if case .reasoningDelta(let text) = part { print(text, terminator: "") }
            if case .textDelta(let text) = part { print(text, terminator: "") }
        }
    }
}

