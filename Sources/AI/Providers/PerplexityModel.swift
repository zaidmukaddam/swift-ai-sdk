import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

private let perplexityConfiguration = OpenAICompatibleServiceConfiguration(
    providerName: "perplexity",
    baseURL: URL(string: "https://api.perplexity.ai")!,
    apiKeyEnvironmentVariable: "PERPLEXITY_API_KEY"
)

public struct PerplexityModel: OpenAICompatibleLanguageModel {
    static let configuration = perplexityConfiguration
    let engine: OpenAIChatModel

    public init(
        _ modelID: String, apiKey: String? = nil, baseURL: URL? = nil,
        headers: [String: String] = [:], queryParams: [String: String] = [:],
        urlSession: URLSession = .shared
    ) {
        engine = perplexityConfiguration.makeModel(
            modelID, apiKey: apiKey, baseURL: baseURL, headers: headers,
            queryParams: queryParams, urlSession: urlSession
        )
    }
}
