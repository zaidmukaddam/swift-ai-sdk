import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

private let lmStudioConfiguration = OpenAICompatibleServiceConfiguration(
    providerName: "lmstudio",
    baseURL: URL(string: "http://localhost:1234/v1")!,
    apiKeyEnvironmentVariable: nil
)

public struct LMStudioModel: OpenAICompatibleLanguageModel {
    static let configuration = lmStudioConfiguration
    let engine: OpenAIChatModel

    public init(
        _ modelID: String, apiKey: String? = nil, baseURL: URL? = nil,
        headers: [String: String] = [:], queryParams: [String: String] = [:],
        urlSession: URLSession = .shared
    ) {
        engine = lmStudioConfiguration.makeModel(
            modelID, apiKey: apiKey, baseURL: baseURL, headers: headers,
            queryParams: queryParams, urlSession: urlSession
        )
    }
}

public extension OpenAICompatibleProvider {
    @available(*, deprecated, message: "Use LMStudioModel for language models.")
    static func lmStudio(
        baseURL: URL = URL(string: "http://localhost:1234/v1")!
    ) -> OpenAICompatibleProvider {
        lmStudioConfiguration.makeProvider(apiKey: nil, baseURL: baseURL)
    }
}
