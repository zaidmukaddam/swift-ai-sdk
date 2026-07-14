import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

private let vercelConfiguration = OpenAICompatibleServiceConfiguration(
    providerName: "vercel",
    baseURL: URL(string: "https://api.v0.dev/v1")!,
    apiKeyEnvironmentVariable: "VERCEL_API_KEY"
)

public struct VercelModel: OpenAICompatibleLanguageModel {
    static let configuration = vercelConfiguration
    let engine: OpenAIChatModel

    public init(
        _ modelID: String, apiKey: String? = nil, baseURL: URL? = nil,
        headers: [String: String] = [:], queryParams: [String: String] = [:],
        urlSession: URLSession = .shared
    ) {
        engine = vercelConfiguration.makeModel(
            modelID, apiKey: apiKey, baseURL: baseURL, headers: headers,
            queryParams: queryParams, urlSession: urlSession
        )
    }
}

public extension OpenAICompatibleProvider {
    @available(*, deprecated, message: "Use VercelModel for language models.")
    static func vercel(apiKey: String? = nil) -> OpenAICompatibleProvider {
        vercelConfiguration.makeProvider(apiKey: apiKey)
    }
}
