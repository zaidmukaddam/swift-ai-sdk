import AI

func example_onDeviceOrCloud() async throws {
    let model: any LanguageModel
    #if canImport(FoundationModels)
    if #available(iOS 26.0, macOS 26.0, *) {
        model = FoundationModelsModel.orFallback(AnthropicModel("claude-sonnet-5", apiKey: myKey))
    } else {
        model = AnthropicModel("claude-sonnet-5", apiKey: myKey)
    }
    #else
    model = AnthropicModel("claude-sonnet-5", apiKey: myKey)
    #endif

    let result = try await generateText(
        model: model,
        prompt: "Summarize: Swift concurrency in one line."
    )
    print("[\(result.text)] via \(model.provider)/\(model.modelID)")
}
