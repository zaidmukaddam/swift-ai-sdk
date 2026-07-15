import AI

enum HuggingFaceExamples {
    static func routerChat() async throws {
        let result = try await generateText(
            model: HuggingFaceModel("meta-llama/Llama-3.3-70B-Instruct"),
            prompt: "Explain rope embeddings in two sentences."
        )
        print(result.text)
    }
}
