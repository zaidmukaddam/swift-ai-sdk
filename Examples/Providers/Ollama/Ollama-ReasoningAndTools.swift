import AI

extension OllamaExamples {
    static func reasoningAndTools() async throws {
        let model = wrapLanguageModel(
            model: OllamaModel("qwen3-coder-next"),
            middleware: [.extractReasoning(tag: "think")]
        )
        let result = try await generateText(
            model: model,
            prompt: "Check the weather in Mumbai and explain your answer.",
            tools: [exampleWeatherTool()]
        )
        print(result.reasoningText)
        print(result.text)
    }
}
