import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

private let openRouterConfiguration = OpenAICompatibleServiceConfiguration(
    providerName: "openrouter",
    baseURL: URL(string: "https://openrouter.ai/api/v1")!,
    apiKeyEnvironmentVariable: "OPENROUTER_API_KEY"
)

public struct OpenRouterModel: OpenAICompatibleLanguageModel {
    static let configuration = openRouterConfiguration
    let engine: OpenAIChatModel

    public init(
        _ modelID: String, apiKey: String? = nil, baseURL: URL? = nil,
        headers: [String: String] = [:], queryParams: [String: String] = [:],
        urlSession: URLSession = .shared
    ) {
        engine = openRouterConfiguration.makeModel(
            modelID, apiKey: apiKey, baseURL: baseURL, headers: headers,
            queryParams: queryParams, urlSession: urlSession
        )
    }
}

public extension OpenAICompatibleProvider {
    @available(*, deprecated, message: "Use OpenRouterModel for language models.")
    static func openRouter(apiKey: String? = nil) -> OpenAICompatibleProvider {
        openRouterConfiguration.makeProvider(apiKey: apiKey)
    }
}
