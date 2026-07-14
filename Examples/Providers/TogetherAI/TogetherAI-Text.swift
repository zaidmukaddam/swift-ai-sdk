import AI

enum TogetherAIExamples {
    static func text() async throws {
        let result = streamText(
            model: TogetherAIModel("MiniMaxAI/MiniMax-M3"),
            prompt: "Explain actor isolation in one paragraph."
        )
        for try await text in result.textStream {
            print(text, terminator: "")
        }
    }
}
