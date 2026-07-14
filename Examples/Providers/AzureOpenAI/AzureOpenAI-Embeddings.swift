import AI

extension AzureOpenAIExamples {
    static func embeddings() async throws {
        let azure = AzureOpenAIProvider(resourceName: "my-resource", apiVersion: "v1")
        let result = try await embed(
            model: azure.textEmbeddingModel("my-embedding-deployment"),
            value: "Swift actors"
        )
        print(result.embedding.count)
    }
}

