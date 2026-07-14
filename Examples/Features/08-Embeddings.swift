import AI

func example_embeddings() async throws {
    let model = OpenAIEmbeddingModel("text-embedding-3-small", apiKey: openAIKey)

    let result = try await embedMany(model: model, values: [
        "sunny day at the beach",
        "rainy afternoon in the city"
    ])

    print("similarity:", cosineSimilarity(result.embeddings[0], result.embeddings[1]))
}

func example_semanticSearch(query: String, corpus: [String]) async throws -> String? {
    let model = OpenAIEmbeddingModel("text-embedding-3-small", apiKey: openAIKey)

    let docs = try await embedMany(model: model, values: corpus)
    let q = try await embed(model: model, value: query)

    return zip(corpus, docs.embeddings)
        .max { cosineSimilarity($0.1, q.embedding) < cosineSimilarity($1.1, q.embedding) }?
        .0
}
