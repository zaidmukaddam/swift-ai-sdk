import Foundation

public protocol EmbeddingModel: Sendable {
    var provider: String { get }
    var modelID: String { get }
    func embed(_ texts: [String]) async throws -> EmbeddingResponse
}

public struct EmbeddingResponse: Sendable {
    public var embeddings: [[Double]]
    public var usage: Usage

    public init(embeddings: [[Double]], usage: Usage = Usage()) {
        self.embeddings = embeddings
        self.usage = usage
    }
}

public struct EmbedResult: Sendable {
    public var embedding: [Double]
    public var usage: Usage
}

public struct EmbedManyResult: Sendable {
    public var embeddings: [[Double]]
    public var usage: Usage
}

public func embed(
    model: any EmbeddingModel,
    value: String,
    maxRetries: Int = 2
) async throws -> EmbedResult {
    let response = try await Retry.withRetries(maxRetries) { try await model.embed([value]) }
    guard let first = response.embeddings.first else {
        throw AIError.decoding("Embedding response contained no vectors")
    }
    return EmbedResult(embedding: first, usage: response.usage)
}

public func embedMany(
    model: any EmbeddingModel,
    values: [String],
    maxBatchSize: Int? = nil,
    maxRetries: Int = 2
) async throws -> EmbedManyResult {
    guard !values.isEmpty else { return EmbedManyResult(embeddings: [], usage: Usage()) }
    if let maxBatchSize, maxBatchSize < 1 {
        throw AIError.invalidRequest("maxBatchSize must be at least 1, got \(maxBatchSize)")
    }

    let batchSize = maxBatchSize ?? values.count
    var embeddings: [[Double]] = []
    var usage = Usage()
    var start = 0
    while start < values.count {
        let batch = Array(values[start ..< min(start + batchSize, values.count)])
        let response = try await Retry.withRetries(maxRetries) { try await model.embed(batch) }
        guard response.embeddings.count == batch.count else {
            throw AIError.decoding(
                "Expected \(batch.count) embeddings, got \(response.embeddings.count)"
            )
        }
        embeddings.append(contentsOf: response.embeddings)
        usage = usage + response.usage
        start += batchSize
    }
    return EmbedManyResult(embeddings: embeddings, usage: usage)
}

public func cosineSimilarity(_ a: [Double], _ b: [Double]) -> Double {
    guard a.count == b.count, !a.isEmpty else { return 0 }
    var dot = 0.0, normA = 0.0, normB = 0.0
    for i in a.indices {
        dot += a[i] * b[i]
        normA += a[i] * a[i]
        normB += b[i] * b[i]
    }
    let denominator = (normA * normB).squareRoot()
    return denominator == 0 ? 0 : dot / denominator
}
