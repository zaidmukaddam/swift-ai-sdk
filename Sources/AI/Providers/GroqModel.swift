import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

private let groqConfiguration = OpenAICompatibleServiceConfiguration(
    providerName: "groq",
    baseURL: URL(string: "https://api.groq.com/openai/v1")!,
    apiKeyEnvironmentVariable: "GROQ_API_KEY"
)

public struct GroqModel: OpenAICompatibleLanguageModel {
    static let configuration = groqConfiguration
    let engine: OpenAIChatModel

    public init(
        _ modelID: String, apiKey: String? = nil, baseURL: URL? = nil,
        headers: [String: String] = [:], queryParams: [String: String] = [:],
        urlSession: URLSession = .shared
    ) {
        engine = groqConfiguration.makeModel(
            modelID, apiKey: apiKey, baseURL: baseURL, headers: headers,
            queryParams: queryParams, urlSession: urlSession
        )
    }

    public enum Tools {
        public static func browserSearch(name: String = "browser_search") -> ProviderDefinedTool {
            ProviderDefinedTool(
                provider: "groq", id: "groq.browser_search", name: name,
                args: .object(["type": "browser_search"])
            )
        }

        public static func codeExecution(name: String = "code_execution") -> ProviderDefinedTool {
            ProviderDefinedTool(
                provider: "groq", id: "groq.code_execution", name: name,
                args: .object(["type": "code_execution"])
            )
        }
    }
}
