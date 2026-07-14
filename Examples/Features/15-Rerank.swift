import AI

func example_rerank() async throws {
    let documents = [
        "Carson City is the capital city of Nevada.",
        "Washington, D.C. is the capital of the United States.",
        "Capital punishment has existed in the United States since colonial times."
    ]

    let result = try await rerank(
        model: CohereRerankingModel("rerank-v4-fast"),
        query: "What is the capital of the United States?",
        documents: documents,
        topN: 2
    )

    for ranked in result.rankedDocuments {
        print(String(format: "%.3f", ranked.relevanceScore), ranked.document)
    }
}
