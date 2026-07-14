import AI

enum GoogleExamples {
    static func textAndReasoning() async throws {
        let result = streamText(
            model: GoogleModel("gemini-3.5-flash"),
            prompt: "Explain Swift task groups.",
            reasoning: .high
        )
        for try await part in result.fullStream {
            if case .reasoningDelta(let text) = part { print(text, terminator: "") }
            if case .textDelta(let text) = part { print(text, terminator: "") }
        }
    }
}

