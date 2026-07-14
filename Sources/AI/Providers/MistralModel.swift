import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

private let mistralConfiguration = OpenAICompatibleServiceConfiguration(
    providerName: "mistral",
    baseURL: URL(string: "https://api.mistral.ai/v1")!,
    apiKeyEnvironmentVariable: "MISTRAL_API_KEY"
)

public struct MistralModel: OpenAICompatibleLanguageModel {
    static let configuration = mistralConfiguration
    let engine: OpenAIChatModel

    public init(
        _ modelID: String, apiKey: String? = nil, baseURL: URL? = nil,
        headers: [String: String] = [:], queryParams: [String: String] = [:],
        urlSession: URLSession = .shared
    ) {
        engine = mistralConfiguration.makeModel(
            modelID, apiKey: apiKey, baseURL: baseURL, headers: headers,
            queryParams: queryParams, urlSession: urlSession
        )
    }
}
