import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct PerplexityModel: LanguageModel {
    public var provider: String { engine.provider }
    public var modelID: String { engine.modelID }

    let engine: OpenAIChatModel

    public init(
        _ modelID: String,
        apiKey: String? = nil,
        baseURL: URL = URL(string: "https://api.perplexity.ai")!,
        headers: [String: String] = [:],
        urlSession: URLSession = .shared
    ) {
        self.engine = OpenAIChatModel(
            modelID,
            apiKey: apiKey ?? ProcessInfo.processInfo.environment["PERPLEXITY_API_KEY"] ?? "",
            baseURL: baseURL,
            headers: headers,
            queryParams: [:],
            urlSession: urlSession,
            providerName: "perplexity"
        )
    }

    public func stream(
        _ request: LanguageModelRequest
    ) async throws -> AsyncThrowingStream<StreamPart, Error> {
        try await engine.stream(request)
    }
}
