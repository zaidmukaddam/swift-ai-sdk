import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

private let cerebrasConfiguration = OpenAICompatibleServiceConfiguration(
    providerName: "cerebras",
    baseURL: URL(string: "https://api.cerebras.ai/v1")!,
    apiKeyEnvironmentVariable: "CEREBRAS_API_KEY"
)

public struct CerebrasModel: OpenAICompatibleLanguageModel {
    static let configuration = cerebrasConfiguration
    let engine: OpenAIChatModel

    public init(
        _ modelID: String, apiKey: String? = nil, baseURL: URL? = nil,
        headers: [String: String] = [:], queryParams: [String: String] = [:],
        urlSession: URLSession = .shared
    ) {
        engine = cerebrasConfiguration.makeModel(
            modelID, apiKey: apiKey, baseURL: baseURL, headers: headers,
            queryParams: queryParams, urlSession: urlSession
        )
    }
}

public extension OpenAICompatibleProvider {
    @available(*, deprecated, message: "Use CerebrasModel for language models.")
    static func cerebras(apiKey: String? = nil) -> OpenAICompatibleProvider {
        cerebrasConfiguration.makeProvider(apiKey: apiKey)
    }
}
