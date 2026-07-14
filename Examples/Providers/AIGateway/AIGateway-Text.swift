import AI

enum AIGatewayExamples {
    static func text() async throws {
        let result = streamText(
            model: AIGatewayModel("anthropic/claude-sonnet-5"),
            prompt: "Explain Swift's ownership model.",
            reasoning: .medium
        )
        for try await text in result.textStream {
            print(text, terminator: "")
        }
    }
}
