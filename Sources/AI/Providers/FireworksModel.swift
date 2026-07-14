import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

private let fireworksConfiguration = OpenAICompatibleServiceConfiguration(
    providerName: "fireworks",
    baseURL: URL(string: "https://api.fireworks.ai/inference/v1")!,
    apiKeyEnvironmentVariable: "FIREWORKS_API_KEY"
)

public struct FireworksModel: OpenAICompatibleLanguageModel {
    static let configuration = fireworksConfiguration
    let engine: OpenAIChatModel

    public init(
        _ modelID: String, apiKey: String? = nil, baseURL: URL? = nil,
        headers: [String: String] = [:], queryParams: [String: String] = [:],
        urlSession: URLSession = .shared
    ) {
        engine = fireworksConfiguration.makeModel(
            modelID, apiKey: apiKey, baseURL: baseURL, headers: headers,
            queryParams: queryParams, urlSession: urlSession
        )
    }
}

public extension OpenAICompatibleProvider {
    @available(*, deprecated, message: "Use FireworksModel for language models.")
    static func fireworks(apiKey: String? = nil) -> OpenAICompatibleProvider {
        fireworksConfiguration.makeProvider(apiKey: apiKey)
    }
}
