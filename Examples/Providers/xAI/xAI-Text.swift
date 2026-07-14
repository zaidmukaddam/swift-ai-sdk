import AI

enum XAIExamples {
    static func responsesChatAndReasoning() async throws {
        let responses = streamText(
            model: XaiModel("grok-4.5"),
            prompt: "Explain Swift's Sendable protocol.",
            reasoning: .high
        )
        for try await part in responses.fullStream {
            if case .reasoningDelta(let text) = part { print(text, terminator: "") }
            if case .textDelta(let text) = part { print(text, terminator: "") }
        }

        let chat = try await generateText(
            model: XaiModel.chat("grok-4.5"),
            prompt: "Give one Sendable example."
        )
        print(chat.text)
    }
}

