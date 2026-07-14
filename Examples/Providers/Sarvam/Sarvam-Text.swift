import AI

enum SarvamExamples {
    static func textAndReasoning() async throws {
        let result = streamText(
            model: SarvamModel("sarvam-105b"),
            prompt: "भारत के बारे में एक रोचक तथ्य बताओ।",
            reasoning: .high
        )
        for try await part in result.fullStream {
            if case .reasoningDelta(let text) = part { print(text, terminator: "") }
            if case .textDelta(let text) = part { print(text, terminator: "") }
        }
    }
}

