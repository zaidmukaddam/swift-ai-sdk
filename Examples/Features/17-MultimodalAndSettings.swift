import AI
import Foundation

func example_vision() async throws {
    let photo = try Data(contentsOf: URL(fileURLWithPath: "/tmp/fox.png"))

    let result = try await generateText(
        model: AnthropicModel("claude-sonnet-5"),
        messages: [Message(role: .user, content: [
            .text("What animal is in this photo?"),
            .image(ImageContent(data: photo))
        ])]
    )
    print(result.text)
}

func example_settings() async throws {
    let result = try await generateText(
        model: OpenAIModel("gpt-5.6-sol"),
        prompt: "Name a color.",
        toolChoice: .none,
        temperature: 0.7,
        topP: 0.9,
        topK: 40,
        presencePenalty: 0.5,
        frequencyPenalty: 0.3,
        seed: 42,
        onFinish: { result in print("used \(result.usage.totalTokens) tokens") },
        onError: { error in print("failed:", error) }
    )
    print(result.text)
}

func example_reasoning() async throws {
    let claude = try await generateText(
        model: AnthropicModel("claude-sonnet-5"),
        prompt: "How many people will live in the world in 2040?",
        reasoning: .medium
    )
    print(claude.reasoningText, claude.text)

    let gemini = streamText(
        model: GoogleModel("gemini-3.5-flash"),
        prompt: "Explain the Riemann hypothesis in simple terms.",
        reasoning: .high
    )
    for try await part in gemini.fullStream {
        if case .reasoningDelta(let thought) = part { print(thought, terminator: "") }
        if case .textDelta(let text) = part { print(text, terminator: "") }
    }

    _ = try await generateText(
        model: AnthropicModel("claude-sonnet-4-5"),
        prompt: "Plan a garden.",
        reasoning: .low,
        providerOptions: [
            "thinking": ["type": "enabled", "budget_tokens": 12000]
        ]
    )
}
