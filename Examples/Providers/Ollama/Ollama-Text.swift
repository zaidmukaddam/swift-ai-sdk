import AI

enum OllamaExamples {
    static func text() async throws {
        let result = streamText(
            model: OllamaModel("gemma4"),
            prompt: "Explain Swift optionals."
        )
        for try await text in result.textStream {
            print(text, terminator: "")
        }
    }
}
