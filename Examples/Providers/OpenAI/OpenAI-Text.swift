import AI

enum OpenAIExamples {
    static func responsesAndChat() async throws {
        let responses = streamText(
            model: OpenAIModel("gpt-5.6-sol"),
            prompt: "Explain Swift actors.",
            reasoning: .xhigh
        )
        for try await part in responses.fullStream {
            if case .reasoningDelta(let text) = part { print(text, terminator: "") }
            if case .textDelta(let text) = part { print(text, terminator: "") }
        }

        let chat = try await generateText(
            model: OpenAIModel.chat("gpt-5.6-terra"),
            prompt: "Give me one actor example."
        )
        print(chat.text)
    }
}

