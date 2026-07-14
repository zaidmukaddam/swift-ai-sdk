import AI

enum FireworksExamples {
    static func text() async throws {
        let result = streamText(
            model: FireworksModel("accounts/fireworks/models/glm-5p2"),
            prompt: "Explain Sendable in three sentences.",
            reasoning: .high
        )
        for try await part in result.fullStream {
            if case .reasoningDelta(let text) = part { print(text, terminator: "") }
            if case .textDelta(let text) = part { print(text, terminator: "") }
        }
    }
}
