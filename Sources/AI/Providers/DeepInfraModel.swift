import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

private let deepInfraConfiguration = OpenAICompatibleServiceConfiguration(
    providerName: "deepinfra",
    baseURL: URL(string: "https://api.deepinfra.com/v1/openai")!,
    apiKeyEnvironmentVariable: "DEEPINFRA_API_KEY"
)

public struct DeepInfraModel: OpenAICompatibleLanguageModel {
    static let configuration = deepInfraConfiguration
    let engine: OpenAIChatModel

    public init(
        _ modelID: String, apiKey: String? = nil, baseURL: URL? = nil,
        headers: [String: String] = [:], queryParams: [String: String] = [:],
        urlSession: URLSession = .shared
    ) {
        engine = deepInfraConfiguration.makeModel(
            modelID, apiKey: apiKey, baseURL: baseURL, headers: headers,
            queryParams: queryParams, urlSession: urlSession
        )
    }
}

public struct DeepInfraEmbeddingModel: OpenAICompatibleEmbeddingModel {
    let engine: OpenAIEmbeddingModel

    public init(
        _ modelID: String, apiKey: String? = nil, baseURL: URL? = nil,
        headers: [String: String] = [:], urlSession: URLSession = .shared
    ) {
        engine = deepInfraConfiguration.makeEmbeddingModel(
            modelID, apiKey: apiKey, baseURL: baseURL, headers: headers, urlSession: urlSession
        )
    }
}

public extension OpenAICompatibleProvider {
    @available(*, deprecated, message: "Use DeepInfraModel for language models.")
    static func deepInfra(apiKey: String? = nil) -> OpenAICompatibleProvider {
        deepInfraConfiguration.makeProvider(apiKey: apiKey)
    }
}
