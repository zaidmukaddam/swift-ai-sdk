import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

private let sarvamConfiguration = OpenAICompatibleServiceConfiguration(
    providerName: "sarvam",
    baseURL: URL(string: "https://api.sarvam.ai/v1")!,
    apiKeyEnvironmentVariable: "SARVAM_API_KEY"
)

public struct SarvamModel: OpenAICompatibleLanguageModel {
    static let configuration = sarvamConfiguration
    let engine: OpenAIChatModel

    public init(
        _ modelID: String, apiKey: String? = nil, baseURL: URL? = nil,
        headers: [String: String] = [:], queryParams: [String: String] = [:],
        urlSession: URLSession = .shared
    ) {
        engine = sarvamConfiguration.makeModel(
            modelID, apiKey: apiKey, baseURL: baseURL, headers: headers,
            queryParams: queryParams, urlSession: urlSession
        )
    }
}

public extension OpenAICompatibleProvider {
    @available(*, deprecated, message: "Use SarvamModel for language models.")
    static func sarvam(apiKey: String? = nil) -> OpenAICompatibleProvider {
        sarvamConfiguration.makeProvider(apiKey: apiKey)
    }
}
