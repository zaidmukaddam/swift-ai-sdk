import AI

enum AmazonBedrockExamples {
    static func textAndReasoning() async throws {
        let result = streamText(
            model: BedrockModel(
                "anthropic.claude-sonnet-4-5-20250929-v1:0",
                region: "us-east-1"
            ),
            prompt: "Explain Swift actors.",
            reasoning: .high
        )
        for try await text in result.textStream {
            print(text, terminator: "")
        }
    }
}

