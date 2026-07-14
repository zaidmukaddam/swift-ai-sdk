import AI

enum AppleFoundationModelsExamples {}

#if canImport(FoundationModels)
@available(iOS 26.0, macOS 26.0, *)
extension AppleFoundationModelsExamples {
    static func textAndStreaming() async throws {
        let model = FoundationModelsModel()
        let generated = try await generateText(model: model, prompt: "Write a rain haiku.")
        print(generated.text)

        let streamed = streamText(model: model, prompt: "Explain Swift actors.")
        for try await text in streamed.textStream {
            print(text, terminator: "")
        }
    }
}
#endif

