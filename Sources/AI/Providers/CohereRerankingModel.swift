import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct CohereRerankingModel: RerankingModel {
    public let provider = "cohere"
    public let modelID: String

    private let apiKey: String
    private let baseURL: URL
    private let headers: [String: String]
    private let urlSession: URLSession

    public init(
        _ modelID: String,
        apiKey: String? = nil,
        baseURL: URL = URL(string: "https://api.cohere.com/v2")!,
        headers: [String: String] = [:],
        urlSession: URLSession = .shared
    ) {
        self.modelID = modelID
        self.apiKey = apiKey ?? ProcessInfo.processInfo.environment["COHERE_API_KEY"] ?? ""
        self.baseURL = baseURL
        self.headers = headers
        self.urlSession = urlSession
    }

    public func rerank(
        query: String, documents: [String], topN: Int?
    ) async throws -> [RankedDocumentIndex] {
        let (data, response) = try await urlSession.data(for: buildURLRequest(
            query: query, documents: documents, topN: topN
        ))
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw AIError.http(status: http.statusCode, body: String(decoding: data, as: UTF8.self))
        }
        let decoded = try JSONDecoder().decode(RerankResponseBody.self, from: data)
        return decoded.results.map {
            RankedDocumentIndex(index: $0.index, relevanceScore: $0.relevance_score)
        }
    }

    func buildURLRequest(query: String, documents: [String], topN: Int?) throws -> URLRequest {
        var urlRequest = URLRequest(url: baseURL.appendingPathComponent("rerank"))
        urlRequest.httpMethod = "POST"
        if !apiKey.isEmpty {
            urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        urlRequest.setValue("application/json", forHTTPHeaderField: "content-type")
        for (field, value) in headers {
            urlRequest.setValue(value, forHTTPHeaderField: field)
        }
        var body: [String: JSONValue] = [
            "model": .string(modelID),
            "query": .string(query),
            "documents": .array(documents.map { .string($0) })
        ]
        if let topN { body["top_n"] = .number(Double(topN)) }
        urlRequest.httpBody = try JSONEncoder().encode(JSONValue.object(body))
        return urlRequest
    }
}

private struct RerankResponseBody: Decodable {
    var results: [Item]

    struct Item: Decodable {
        var index: Int
        var relevance_score: Double
    }
}
