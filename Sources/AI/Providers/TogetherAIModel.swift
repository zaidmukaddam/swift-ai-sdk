import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

private let togetherAIConfiguration = OpenAICompatibleServiceConfiguration(
    providerName: "togetherai",
    baseURL: URL(string: "https://api.together.xyz/v1")!,
    apiKeyEnvironmentVariable: "TOGETHER_API_KEY"
)

public struct TogetherAIModel: OpenAICompatibleLanguageModel {
    static let configuration = togetherAIConfiguration
    let engine: OpenAIChatModel

    public init(
        _ modelID: String, apiKey: String? = nil, baseURL: URL? = nil,
        headers: [String: String] = [:], queryParams: [String: String] = [:],
        urlSession: URLSession = .shared
    ) {
        engine = togetherAIConfiguration.makeModel(
            modelID, apiKey: apiKey, baseURL: baseURL, headers: headers,
            queryParams: queryParams, urlSession: urlSession
        )
    }
}

public struct TogetherAIEmbeddingModel: OpenAICompatibleEmbeddingModel {
    let engine: OpenAIEmbeddingModel

    public init(
        _ modelID: String, apiKey: String? = nil, baseURL: URL? = nil,
        headers: [String: String] = [:], urlSession: URLSession = .shared
    ) {
        engine = togetherAIConfiguration.makeEmbeddingModel(
            modelID, apiKey: apiKey, baseURL: baseURL, headers: headers, urlSession: urlSession
        )
    }
}

public extension OpenAICompatibleProvider {
    @available(*, deprecated, message: "Use TogetherAIModel for language models.")
    static func togetherAI(apiKey: String? = nil) -> OpenAICompatibleProvider {
        togetherAIConfiguration.makeProvider(apiKey: apiKey)
    }
}
