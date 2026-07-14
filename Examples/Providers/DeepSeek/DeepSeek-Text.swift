import AI

enum DeepSeekExamples {
    static func textAndReasoning() async throws {
        let result = streamText(
            model: DeepSeekModel("deepseek-reasoner"),
            prompt: "Prove that the square root of two is irrational.",
            reasoning: .xhigh
        )
        for try await part in result.fullStream {
            if case .reasoningDelta(let text) = part { print(text, terminator: "") }
            if case .textDelta(let text) = part { print(text, terminator: "") }
        }
    }
}
