import AI

extension CohereExamples {
    static func embeddings() async throws {
        let result = try await embedMany(
            model: CohereEmbeddingModel("embed-v4.0"),
            values: ["Swift actors", "task groups", "oil painting"]
        )
        print(cosineSimilarity(result.embeddings[0], result.embeddings[1]))
    }
}

