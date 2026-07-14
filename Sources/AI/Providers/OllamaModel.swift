import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

private let ollamaConfiguration = OpenAICompatibleServiceConfiguration(
    providerName: "ollama",
    baseURL: URL(string: "http://localhost:11434/v1")!,
    apiKeyEnvironmentVariable: nil
)

public struct OllamaModel: OpenAICompatibleLanguageModel {
    static let configuration = ollamaConfiguration
    let engine: OpenAIChatModel

    public init(
        _ modelID: String, apiKey: String? = nil, baseURL: URL? = nil,
        headers: [String: String] = [:], queryParams: [String: String] = [:],
        urlSession: URLSession = .shared
    ) {
        engine = ollamaConfiguration.makeModel(
            modelID, apiKey: apiKey, baseURL: baseURL, headers: headers,
            queryParams: queryParams, urlSession: urlSession
        )
    }
}

public extension OpenAICompatibleProvider {
    @available(*, deprecated, message: "Use OllamaModel for language models.")
    static func ollama(
        baseURL: URL = URL(string: "http://localhost:11434/v1")!
    ) -> OpenAICompatibleProvider {
        ollamaConfiguration.makeProvider(apiKey: nil, baseURL: baseURL)
    }
}
