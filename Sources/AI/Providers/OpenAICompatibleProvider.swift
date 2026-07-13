import Foundation

public struct OpenAICompatibleProvider: Sendable {
    public var name: String
    public var baseURL: URL
    public var apiKey: String?
    public var headers: [String: String]
    public var queryParams: [String: String]
    private let urlSession: URLSession

    public init(
        name: String,
        baseURL: URL,
        apiKey: String? = nil,
        headers: [String: String] = [:],
        queryParams: [String: String] = [:],
        urlSession: URLSession = .shared
    ) {
        self.name = name
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.headers = headers
        self.queryParams = queryParams
        self.urlSession = urlSession
    }

    public func callAsFunction(_ modelID: String) -> OpenAIChatModel {
        languageModel(modelID)
    }

    public func languageModel(_ modelID: String) -> OpenAIChatModel {
        OpenAIChatModel(
            modelID,
            apiKey: apiKey ?? "",
            baseURL: baseURL,
            headers: headers,
            queryParams: queryParams,
            urlSession: urlSession,
            providerName: name
        )
    }

    public func textEmbeddingModel(_ modelID: String) -> OpenAIEmbeddingModel {
        OpenAIEmbeddingModel(
            modelID,
            apiKey: apiKey ?? "",
            baseURL: baseURL,
            headers: headers,
            urlSession: urlSession,
            providerName: name
        )
    }
}

public extension OpenAICompatibleProvider {
    private static func preset(
        _ name: String, _ url: String, _ apiKey: String?, _ envVar: String
    ) -> OpenAICompatibleProvider {
        OpenAICompatibleProvider(
            name: name,
            baseURL: URL(string: url)!,
            apiKey: apiKey ?? ProcessInfo.processInfo.environment[envVar]
        )
    }

    static func togetherAI(apiKey: String? = nil) -> OpenAICompatibleProvider {
        preset("togetherai", "https://api.together.xyz/v1", apiKey, "TOGETHER_API_KEY")
    }

    static func fireworks(apiKey: String? = nil) -> OpenAICompatibleProvider {
        preset("fireworks", "https://api.fireworks.ai/inference/v1", apiKey, "FIREWORKS_API_KEY")
    }

    static func cerebras(apiKey: String? = nil) -> OpenAICompatibleProvider {
        preset("cerebras", "https://api.cerebras.ai/v1", apiKey, "CEREBRAS_API_KEY")
    }

    static func openRouter(apiKey: String? = nil) -> OpenAICompatibleProvider {
        preset("openrouter", "https://openrouter.ai/api/v1", apiKey, "OPENROUTER_API_KEY")
    }

    static func ollama(
        baseURL: URL = URL(string: "http://localhost:11434/v1")!
    ) -> OpenAICompatibleProvider {
        OpenAICompatibleProvider(name: "ollama", baseURL: baseURL)
    }

    static func lmStudio(
        baseURL: URL = URL(string: "http://localhost:1234/v1")!
    ) -> OpenAICompatibleProvider {
        OpenAICompatibleProvider(name: "lmstudio", baseURL: baseURL)
    }
}
