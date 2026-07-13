import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct OpenAIEmbeddingModel: EmbeddingModel {
    public let provider: String
    public let modelID: String

    private let apiKey: String
    private let baseURL: URL
    private let headers: [String: String]
    private let urlSession: URLSession

    public init(
        _ modelID: String,
        apiKey: String? = nil,
        baseURL: URL = URL(string: "https://api.openai.com/v1")!,
        headers: [String: String] = [:],
        urlSession: URLSession = .shared
    ) {
        self.init(
            modelID,
            apiKey: apiKey ?? ProcessInfo.processInfo.environment["OPENAI_API_KEY"] ?? "",
            baseURL: baseURL,
            headers: headers,
            urlSession: urlSession,
            providerName: "openai"
        )
    }

    init(
        _ modelID: String,
        apiKey: String,
        baseURL: URL,
        headers: [String: String],
        urlSession: URLSession,
        providerName: String
    ) {
        self.modelID = modelID
        self.apiKey = apiKey
        self.baseURL = baseURL
        self.headers = headers
        self.urlSession = urlSession
        self.provider = providerName
    }

    public func embed(_ texts: [String]) async throws -> EmbeddingResponse {
        var urlRequest = URLRequest(url: baseURL.appendingPathComponent("embeddings"))
        urlRequest.httpMethod = "POST"
        if !apiKey.isEmpty {
            urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        urlRequest.setValue("application/json", forHTTPHeaderField: "content-type")
        for (field, value) in headers {
            urlRequest.setValue(value, forHTTPHeaderField: field)
        }
        urlRequest.httpBody = try JSONEncoder().encode(JSONValue.object([
            "model": .string(modelID),
            "input": .array(texts.map { .string($0) })
        ]))

        let (data, response) = try await urlSession.data(for: urlRequest)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw AIError.http(status: http.statusCode, body: String(decoding: data, as: UTF8.self))
        }

        let decoded = try JSONDecoder().decode(EmbeddingsResponseBody.self, from: data)
        let ordered = decoded.data.sorted { $0.index < $1.index }.map(\.embedding)
        return EmbeddingResponse(
            embeddings: ordered,
            usage: Usage(inputTokens: decoded.usage?.prompt_tokens ?? 0, outputTokens: 0)
        )
    }
}

private struct EmbeddingsResponseBody: Decodable {
    var data: [Item]
    var usage: UsageBody?

    struct Item: Decodable {
        var index: Int
        var embedding: [Double]
    }
    struct UsageBody: Decodable {
        var prompt_tokens: Int?
    }
}
