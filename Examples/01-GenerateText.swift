import AI

func example_generate() async throws {
    let model = AnthropicModel("claude-opus-4-8", apiKey: myKey)

    let result = try await generateText(
        model: model,
        system: "You are concise.",
        prompt: "Name three primary colors."
    )

    print(result.text)
    print("tokens: \(result.usage.totalTokens)")
}
