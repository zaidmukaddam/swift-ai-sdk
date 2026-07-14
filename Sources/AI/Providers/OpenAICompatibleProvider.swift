import Foundation

public struct OpenAICompatibleProvider: Sendable {
    public var name: String
    public var baseURL: URL
    public var apiKey: String?
    public var headers: [String: String]
    public var queryParams: [String: String]
    private let urlSession: URLSession

    public init(
        name: String,
        baseURL: URL,
        apiKey: String? = nil,
        headers: [String: String] = [:],
        queryParams: [String: String] = [:],
        urlSession: URLSession = .shared
    ) {
        self.name = name
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.headers = headers
        self.queryParams = queryParams
        self.urlSession = urlSession
    }

    public func callAsFunction(_ modelID: String) -> OpenAIChatModel {
        languageModel(modelID)
    }

    public func languageModel(_ modelID: String) -> OpenAIChatModel {
        OpenAIChatModel(
            modelID,
            apiKey: apiKey ?? "",
            baseURL: baseURL,
            headers: headers,
            queryParams: queryParams,
            urlSession: urlSession,
            providerName: name
        )
    }

    public func textEmbeddingModel(_ modelID: String) -> OpenAIEmbeddingModel {
        OpenAIEmbeddingModel(
            modelID,
            apiKey: apiKey ?? "",
            baseURL: baseURL,
            headers: headers,
            urlSession: urlSession,
            providerName: name
        )
    }
}
