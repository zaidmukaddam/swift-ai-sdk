import AI

func example_middleware() async throws {
    let base = OllamaModel("qwen3")
    let model = wrapLanguageModel(
        model: base,
        middleware: [
            .extractReasoning(tag: "think"),
            .defaultSettings(temperature: 0.2)
        ]
    )

    let result = try await generateText(model: model, prompt: "17 * 23?")
    print("thinking:", result.reasoningText)
    print("answer:", result.text)
}

func example_customMiddleware() -> LanguageModelMiddleware {
    LanguageModelMiddleware(
        transformRequest: { request in
            print("sending \(request.messages.count) messages")
            return request
        }
    )
}
