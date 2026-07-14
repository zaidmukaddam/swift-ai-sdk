import AI

enum BasetenExamples {
    static func text() async throws {
        let result = streamText(
            model: BasetenModel("deepseek-ai/DeepSeek-V4-Pro"),
            prompt: "Explain async let in Swift.",
            reasoning: .high
        )
        for try await text in result.textStream {
            print(text, terminator: "")
        }
    }
}
