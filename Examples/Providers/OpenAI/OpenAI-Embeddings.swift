import AI

extension OpenAIExamples {
    static func embeddings() async throws {
        let result = try await embedMany(
            model: OpenAIEmbeddingModel("text-embedding-3-small"),
            values: ["Swift actors", "structured concurrency", "watercolor painting"]
        )
        print(cosineSimilarity(result.embeddings[0], result.embeddings[1]))
    }
}

