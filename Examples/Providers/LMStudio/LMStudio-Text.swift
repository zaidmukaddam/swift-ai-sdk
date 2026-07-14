import AI

enum LMStudioExamples {
    static func text() async throws {
        let result = streamText(
            model: LMStudioModel("openai/gpt-oss-20b"),
            prompt: "Explain Swift result builders."
        )
        for try await text in result.textStream {
            print(text, terminator: "")
        }
    }
}
