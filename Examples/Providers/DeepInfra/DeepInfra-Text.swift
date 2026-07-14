import AI

enum DeepInfraExamples {
    static func text() async throws {
        let result = streamText(
            model: DeepInfraModel("deepseek-ai/DeepSeek-V4-Pro"),
            prompt: "Explain copy-on-write in Swift.",
            reasoning: .high
        )
        for try await text in result.textStream {
            print(text, terminator: "")
        }
    }
}
