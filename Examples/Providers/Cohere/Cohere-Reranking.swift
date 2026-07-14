import AI

extension CohereExamples {
    static func reranking() async throws {
        let result = try await rerank(
            model: CohereRerankingModel("rerank-v4-fast"),
            query: "How do Swift actors prevent data races?",
            documents: [
                "Actors isolate mutable state.",
                "Structs use value semantics.",
                "SwiftUI describes user interfaces."
            ],
            topN: 2
        )
        print(result.rankedDocuments)
    }
}

