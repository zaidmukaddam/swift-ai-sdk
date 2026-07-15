import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

private let moonshotConfiguration = OpenAICompatibleServiceConfiguration(
    providerName: "moonshot",
    baseURL: URL(string: "https://api.moonshot.ai/v1")!,
    apiKeyEnvironmentVariable: "MOONSHOT_API_KEY"
)

public struct MoonshotModel: OpenAICompatibleLanguageModel {
    static let configuration = moonshotConfiguration
    let engine: OpenAIChatModel

    public init(
        _ modelID: String, apiKey: String? = nil, baseURL: URL? = nil,
        headers: [String: String] = [:], queryParams: [String: String] = [:],
        urlSession: URLSession = .shared
    ) {
        engine = moonshotConfiguration.makeModel(
            modelID, apiKey: apiKey, baseURL: baseURL, headers: headers,
            queryParams: queryParams, urlSession: urlSession
        )
    }
}
