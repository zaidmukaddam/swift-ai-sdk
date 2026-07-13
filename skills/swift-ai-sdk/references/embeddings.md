# Embeddings and reranking

`embed`, `embedMany`, `cosineSimilarity`, and `rerank` are top-level functions in `import AI`. Embedding models conform to `EmbeddingModel`; rerankers to `RerankingModel`.

## embed

```swift
public func embed(
    model: any EmbeddingModel,
    value: String,
    maxRetries: Int = 2
) async throws -> EmbedResult

public struct EmbedResult: Sendable {
    public var embedding: [Double]
    public var usage: Usage
}
```

```swift
import AI

let model = OpenAIEmbeddingModel("text-embedding-3-small")
let result = try await embed(model: model, value: "sunny day at the beach")
result.embedding   // [Double]
result.usage       // token accounting
```

## embedMany

Batches automatically. Pass `maxBatchSize` to respect a provider's per-request limit; the call splits the inputs and concatenates the results in input order.

```swift
public func embedMany(
    model: any EmbeddingModel,
    values: [String],
    maxBatchSize: Int? = nil,
    maxRetries: Int = 2
) async throws -> EmbedManyResult

public struct EmbedManyResult: Sendable {
    public var embeddings: [[Double]]
    public var usage: Usage
}
```

```swift
let result = try await embedMany(model: model, values: documents, maxBatchSize: 96)
result.embeddings   // one vector per input, in order
```

Batches run sequentially, each with its own retry envelope; `usage` is summed. An empty `values` returns empty results. `maxBatchSize < 1` throws `AIError.invalidRequest`; a batch whose returned count mismatches the input count throws `AIError.decoding`.

## cosineSimilarity

```swift
public func cosineSimilarity(_ a: [Double], _ b: [Double]) -> Double
```

Returns `0` for mismatched-length or empty vectors, or when either norm is zero (no throw).

```swift
let query = try await embed(model: model, value: "coastal weather")
let docs = try await embedMany(model: model, values: documents)

let ranked = zip(documents, docs.embeddings)
    .map { document, vector in (document, cosineSimilarity(query.embedding, vector)) }
    .sorted { $0.1 > $1.1 }
```

## EmbeddingModel providers

```swift
public protocol EmbeddingModel: Sendable {
    var provider: String { get }
    var modelID: String { get }
    func embed(_ texts: [String]) async throws -> EmbeddingResponse
}

public struct EmbeddingResponse: Sendable {
    public var embeddings: [[Double]]
    public var usage: Usage
}
```

Built-in conformers:

```swift
public struct OpenAIEmbeddingModel: EmbeddingModel {
    public init(_ modelID: String, apiKey: String? = nil,
                baseURL: URL = URL(string: "https://api.openai.com/v1")!,
                headers: [String: String] = [:], urlSession: URLSession = .shared)
}

public struct CohereEmbeddingModel: EmbeddingModel { /* in CohereModel.swift */ }
```

`OpenAIEmbeddingModel` reads `OPENAI_API_KEY` from the environment when `apiKey` is nil. Because it is OpenAI-compatible, point `baseURL` at any compatible endpoint. `CohereEmbeddingModel` uses the same `embed`/`embedMany` call sites.

```swift
let openai = OpenAIEmbeddingModel("text-embedding-3-small")
let cohere = CohereEmbeddingModel("embed-v4.0")
```

## rerank

Given existing candidates, a reranker orders them by relevance in one call instead of N similarity computations.

```swift
public func rerank(
    model: any RerankingModel,
    query: String,
    documents: [String],
    topN: Int? = nil,
    maxRetries: Int = 2
) async throws -> RerankResult

public struct RerankResult: Sendable {
    public var rankedDocuments: [RankedDocument]
    public struct RankedDocument: Sendable, Hashable {
        public var document: String
        public var index: Int          // position in the original documents array
        public var relevanceScore: Double
    }
}
```

```swift
let result = try await rerank(
    model: CohereRerankingModel("rerank-v4-fast"),
    query: "warm places in january",
    documents: candidates,
    topN: 5
)

for ranked in result.rankedDocuments {
    print(String(format: "%.3f", ranked.relevanceScore), ranked.document)
}
```

An empty `documents` returns empty `rankedDocuments`. Results preserve the provider's relevance ordering (not input order); each `RankedDocument.index` maps back to the original array.

## RerankingModel

```swift
public protocol RerankingModel: Sendable {
    var provider: String { get }
    var modelID: String { get }
    func rerank(query: String, documents: [String], topN: Int?) async throws -> [RankedDocumentIndex]
}

public struct RankedDocumentIndex: Sendable, Hashable {
    public var index: Int
    public var relevanceScore: Double
}

public struct CohereRerankingModel: RerankingModel {
    public init(_ modelID: String, apiKey: String? = nil,
                baseURL: URL = URL(string: "https://api.cohere.com/v2")!,
                headers: [String: String] = [:], urlSession: URLSession = .shared)
}
```

`CohereRerankingModel` reads `COHERE_API_KEY` from the environment when `apiKey` is nil. A custom conformer only implements `rerank(query:documents:topN:)` returning `[RankedDocumentIndex]`; the top-level `rerank` maps indices back to documents and drops any out-of-range index.

## Gotchas

- `cosineSimilarity` never throws — it returns `0` on length mismatch, empty input, or a zero-norm vector. Guard against `0` if you need to distinguish "orthogonal" from "invalid".
- `embedMany` runs batches sequentially, not concurrently; ordering is preserved but throughput is bounded by round-trips.
- A provider that returns a different embedding count than the batch size throws `AIError.decoding` — surfaces silent provider truncation.
- `rerank` results are relevance-ordered; use `RankedDocument.index` (not array position) to correlate with your original list.
- Embedding usage reports `inputTokens` only (`outputTokens` is 0).
