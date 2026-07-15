import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct VoyageEmbeddingModel: EmbeddingModel {
    public enum InputType: String, Sendable {
        case query
        case document
    }

    public let provider = "voyage"
    public let modelID: String

    private let apiKey: String
    private let baseURL: URL
    private let inputType: InputType?
    private let outputDimension: Int?
    private let headers: [String: String]
    private let urlSession: URLSession

    static let maxTextsPerCall = 128

    public init(
        _ modelID: String = "voyage-3.5",
        apiKey: String? = nil,
        baseURL: URL = URL(string: "https://api.voyageai.com/v1")!,
        inputType: InputType? = nil,
        outputDimension: Int? = nil,
        headers: [String: String] = [:],
        urlSession: URLSession = .shared
    ) {
        self.modelID = modelID
        self.apiKey = apiKey ?? ProcessInfo.processInfo.environment["VOYAGE_API_KEY"] ?? ""
        self.baseURL = baseURL
        self.inputType = inputType
        self.outputDimension = outputDimension
        self.headers = headers
        self.urlSession = urlSession
    }

    public func embed(_ texts: [String]) async throws -> EmbeddingResponse {
        var embeddings: [[Double]] = []
        var usage = Usage()
        for start in stride(from: 0, to: texts.count, by: Self.maxTextsPerCall) {
            let batch = Array(texts[start..<min(start + Self.maxTextsPerCall, texts.count)])
            let (data, response) = try await urlSession.data(for: try buildURLRequest(batch))
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                throw AIError.http(status: http.statusCode, body: String(decoding: data, as: UTF8.self))
            }
            let decoded = try JSONDecoder().decode(JSONValue.self, from: data)
            embeddings += (decoded["data"]?.arrayValue ?? []).map { item in
                (item["embedding"]?.arrayValue ?? []).compactMap(\.doubleValue)
            }
            usage = usage + Usage(
                inputTokens: decoded["usage"]?["total_tokens"]?.intValue ?? 0
            )
        }
        return EmbeddingResponse(embeddings: embeddings, usage: usage)
    }

    func buildURLRequest(_ texts: [String]) throws -> URLRequest {
        var body: [String: JSONValue] = [
            "model": .string(modelID),
            "input": .array(texts.map { .string($0) })
        ]
        if let inputType { body["input_type"] = .string(inputType.rawValue) }
        if let outputDimension { body["output_dimension"] = .number(Double(outputDimension)) }

        var urlRequest = URLRequest(url: baseURL.appendingPathComponent("embeddings"))
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue("application/json", forHTTPHeaderField: "content-type")
        for (field, value) in headers { urlRequest.setValue(value, forHTTPHeaderField: field) }
        urlRequest.httpBody = try JSONEncoder().encode(JSONValue.object(body))
        return urlRequest
    }
}

public struct VoyageRerankingModel: RerankingModel {
    public let provider = "voyage"
    public let modelID: String

    private let apiKey: String
    private let baseURL: URL
    private let headers: [String: String]
    private let urlSession: URLSession

    public init(
        _ modelID: String = "rerank-2.5",
        apiKey: String? = nil,
        baseURL: URL = URL(string: "https://api.voyageai.com/v1")!,
        headers: [String: String] = [:],
        urlSession: URLSession = .shared
    ) {
        self.modelID = modelID
        self.apiKey = apiKey ?? ProcessInfo.processInfo.environment["VOYAGE_API_KEY"] ?? ""
        self.baseURL = baseURL
        self.headers = headers
        self.urlSession = urlSession
    }

    public func rerank(
        query: String, documents: [String], topN: Int?
    ) async throws -> [RankedDocumentIndex] {
        let (data, response) = try await urlSession.data(
            for: try buildURLRequest(query: query, documents: documents, topN: topN)
        )
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw AIError.http(status: http.statusCode, body: String(decoding: data, as: UTF8.self))
        }
        let decoded = try JSONDecoder().decode(JSONValue.self, from: data)
        return (decoded["data"]?.arrayValue ?? []).compactMap { item in
            guard let index = item["index"]?.intValue else { return nil }
            return RankedDocumentIndex(
                index: index,
                relevanceScore: item["relevance_score"]?.doubleValue ?? 0
            )
        }
    }

    func buildURLRequest(
        query: String, documents: [String], topN: Int?
    ) throws -> URLRequest {
        var body: [String: JSONValue] = [
            "model": .string(modelID),
            "query": .string(query),
            "documents": .array(documents.map { .string($0) })
        ]
        if let topN { body["top_k"] = .number(Double(topN)) }

        var urlRequest = URLRequest(url: baseURL.appendingPathComponent("rerank"))
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue("application/json", forHTTPHeaderField: "content-type")
        for (field, value) in headers { urlRequest.setValue(value, forHTTPHeaderField: field) }
        urlRequest.httpBody = try JSONEncoder().encode(JSONValue.object(body))
        return urlRequest
    }
}
