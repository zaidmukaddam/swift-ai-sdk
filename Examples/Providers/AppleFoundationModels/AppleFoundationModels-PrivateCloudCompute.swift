import AI

#if canImport(FoundationModels)
#if compiler(>=6.4)
@available(iOS 27.0, macOS 27.0, *)
extension AppleFoundationModelsExamples {
    static func privateCloudCompute() async throws {
        let model = FoundationModelsModel.privateCloudCompute()
        let result = try await generateText(
            model: model,
            prompt: "Summarize this private request."
        )
        print(result.text)
    }
}
#endif
#endif
