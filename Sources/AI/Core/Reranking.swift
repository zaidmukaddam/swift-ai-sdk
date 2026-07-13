import Foundation

public protocol RerankingModel: Sendable {
    var provider: String { get }
    var modelID: String { get }
    func rerank(query: String, documents: [String], topN: Int?) async throws -> [RankedDocumentIndex]
}

public struct RankedDocumentIndex: Sendable, Hashable {
    public var index: Int
    public var relevanceScore: Double

    public init(index: Int, relevanceScore: Double) {
        self.index = index
        self.relevanceScore = relevanceScore
    }
}

public struct RerankResult: Sendable {
    public var rankedDocuments: [RankedDocument]

    public struct RankedDocument: Sendable, Hashable {
        public var document: String
        public var index: Int
        public var relevanceScore: Double
    }
}

public func rerank(
    model: any RerankingModel,
    query: String,
    documents: [String],
    topN: Int? = nil,
    maxRetries: Int = 2
) async throws -> RerankResult {
    guard !documents.isEmpty else { return RerankResult(rankedDocuments: []) }
    let ranking = try await Retry.withRetries(maxRetries) {
        try await model.rerank(query: query, documents: documents, topN: topN)
    }
    let ranked = ranking.compactMap { entry -> RerankResult.RankedDocument? in
        guard documents.indices.contains(entry.index) else { return nil }
        return RerankResult.RankedDocument(
            document: documents[entry.index],
            index: entry.index,
            relevanceScore: entry.relevanceScore
        )
    }
    return RerankResult(rankedDocuments: ranked)
}
