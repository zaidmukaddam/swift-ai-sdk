import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

private let deepSeekConfiguration = OpenAICompatibleServiceConfiguration(
    providerName: "deepseek",
    baseURL: URL(string: "https://api.deepseek.com")!,
    apiKeyEnvironmentVariable: "DEEPSEEK_API_KEY"
)

public struct DeepSeekModel: OpenAICompatibleLanguageModel {
    static let configuration = deepSeekConfiguration
    let engine: OpenAIChatModel

    public init(
        _ modelID: String, apiKey: String? = nil, baseURL: URL? = nil,
        headers: [String: String] = [:], queryParams: [String: String] = [:],
        urlSession: URLSession = .shared
    ) {
        engine = deepSeekConfiguration.makeModel(
            modelID, apiKey: apiKey, baseURL: baseURL, headers: headers,
            queryParams: queryParams, urlSession: urlSession
        )
    }
}
