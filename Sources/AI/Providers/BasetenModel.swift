import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

private let basetenConfiguration = OpenAICompatibleServiceConfiguration(
    providerName: "baseten",
    baseURL: URL(string: "https://inference.baseten.co/v1")!,
    apiKeyEnvironmentVariable: "BASETEN_API_KEY"
)

public struct BasetenModel: OpenAICompatibleLanguageModel {
    static let configuration = basetenConfiguration
    let engine: OpenAIChatModel

    public init(
        _ modelID: String, apiKey: String? = nil, baseURL: URL? = nil,
        headers: [String: String] = [:], queryParams: [String: String] = [:],
        urlSession: URLSession = .shared
    ) {
        engine = basetenConfiguration.makeModel(
            modelID, apiKey: apiKey, baseURL: baseURL, headers: headers,
            queryParams: queryParams, urlSession: urlSession
        )
    }
}

public struct BasetenEmbeddingModel: OpenAICompatibleEmbeddingModel {
    let engine: OpenAIEmbeddingModel

    public init(
        _ modelID: String, apiKey: String? = nil, baseURL: URL? = nil,
        headers: [String: String] = [:], urlSession: URLSession = .shared
    ) {
        engine = basetenConfiguration.makeEmbeddingModel(
            modelID, apiKey: apiKey, baseURL: baseURL, headers: headers, urlSession: urlSession
        )
    }
}

public extension OpenAICompatibleProvider {
    @available(*, deprecated, message: "Use BasetenModel for language models.")
    static func baseten(apiKey: String? = nil) -> OpenAICompatibleProvider {
        basetenConfiguration.makeProvider(apiKey: apiKey)
    }
}
