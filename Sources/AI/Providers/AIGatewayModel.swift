import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

private let aiGatewayConfiguration = OpenAICompatibleServiceConfiguration(
    providerName: "gateway",
    baseURL: URL(string: "https://ai-gateway.vercel.sh/v1")!,
    apiKeyEnvironmentVariable: "AI_GATEWAY_API_KEY"
)

public struct AIGatewayModel: OpenAICompatibleLanguageModel {
    static let configuration = aiGatewayConfiguration
    let engine: OpenAIChatModel

    public init(
        _ modelID: String, apiKey: String? = nil, baseURL: URL? = nil,
        headers: [String: String] = [:], queryParams: [String: String] = [:],
        urlSession: URLSession = .shared
    ) {
        engine = aiGatewayConfiguration.makeModel(
            modelID, apiKey: apiKey, baseURL: baseURL, headers: headers,
            queryParams: queryParams, urlSession: urlSession
        )
    }
}

public extension OpenAICompatibleProvider {
    @available(*, deprecated, message: "Use AIGatewayModel for language models.")
    static func gateway(apiKey: String? = nil) -> OpenAICompatibleProvider {
        aiGatewayConfiguration.makeProvider(apiKey: apiKey)
    }
}
