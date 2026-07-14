import AI

#if canImport(FoundationModels)
@available(iOS 26.0, macOS 26.0, *)
extension AppleFoundationModelsExamples {
    static func fallback() async throws {
        let model = FoundationModelsModel.orFallback(
            AnthropicModel("claude-sonnet-5")
        )
        let result = try await generateText(model: model, prompt: "Say hello.")
        print(result.text)
    }

    @MainActor
    static func offlineChat() {
        let chat = ChatSession(transport: LocalChatTransport(
            model: FoundationModelsModel()
        ))
        chat.send("Explain Swift actors.")
    }
}
#endif
