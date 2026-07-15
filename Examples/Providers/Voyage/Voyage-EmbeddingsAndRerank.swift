import AI

enum VoyageExamples {
    static func embeddings() async throws {
        let vectors = try await embedMany(
            model: VoyageEmbeddingModel("voyage-3.5", inputType: .document),
            values: ["Cats are independent.", "Dogs are loyal."]
        )
        print(vectors.embeddings.first?.count ?? 0)
    }

    static func reranking() async throws {
        let ranked = try await rerank(
            model: VoyageRerankingModel("rerank-2.5"),
            query: "How do I cancel my subscription?",
            documents: [
                "Billing lives under Settings > Plan.",
                "Our office hours are 9-5.",
                "Cancel anytime from the Plan page."
            ],
            topN: 2
        )
        for doc in ranked.rankedDocuments {
            print(doc.relevanceScore, doc.document)
        }
    }
}
