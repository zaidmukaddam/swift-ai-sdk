import AI

enum AnthropicExamples {
    static func textAndReasoning() async throws {
        let result = streamText(
            model: AnthropicModel("claude-sonnet-5"),
            prompt: "Explain actor reentrancy.",
            reasoning: .xhigh
        )
        for try await part in result.fullStream {
            if case .reasoningDelta(let text) = part { print(text, terminator: "") }
            if case .textDelta(let text) = part { print(text, terminator: "") }
        }
    }
}

