import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

struct OpenAICompatibleServiceConfiguration: Sendable {
    let providerName: String
    let baseURL: URL
    let apiKeyEnvironmentVariable: String?

    func makeModel(
        _ modelID: String,
        apiKey: String?,
        baseURL: URL?,
        headers: [String: String],
        queryParams: [String: String] = [:],
        urlSession: URLSession
    ) -> OpenAIChatModel {
        OpenAIChatModel(
            modelID,
            apiKey: resolvedAPIKey(apiKey),
            baseURL: baseURL ?? self.baseURL,
            headers: headers,
            queryParams: queryParams,
            urlSession: urlSession,
            providerName: providerName
        )
    }

    func makeEmbeddingModel(
        _ modelID: String,
        apiKey: String?,
        baseURL: URL?,
        headers: [String: String],
        urlSession: URLSession
    ) -> OpenAIEmbeddingModel {
        OpenAIEmbeddingModel(
            modelID,
            apiKey: resolvedAPIKey(apiKey),
            baseURL: baseURL ?? self.baseURL,
            headers: headers,
            urlSession: urlSession,
            providerName: providerName
        )
    }

    func makeProvider(apiKey: String?, baseURL: URL? = nil) -> OpenAICompatibleProvider {
        OpenAICompatibleProvider(
            name: providerName,
            baseURL: baseURL ?? self.baseURL,
            apiKey: resolvedAPIKey(apiKey)
        )
    }

    private func resolvedAPIKey(_ apiKey: String?) -> String {
        apiKey
            ?? apiKeyEnvironmentVariable.flatMap { ProcessInfo.processInfo.environment[$0] }
            ?? ""
    }
}

protocol OpenAICompatibleLanguageModel: LanguageModel {
    var engine: OpenAIChatModel { get }
}

extension OpenAICompatibleLanguageModel {
    public var provider: String { engine.provider }
    public var modelID: String { engine.modelID }

    public func stream(
        _ request: LanguageModelRequest
    ) async throws -> AsyncThrowingStream<StreamPart, Error> {
        try await engine.stream(request)
    }
}

protocol OpenAICompatibleEmbeddingModel: EmbeddingModel {
    var engine: OpenAIEmbeddingModel { get }
}

extension OpenAICompatibleEmbeddingModel {
    public var provider: String { engine.provider }
    public var modelID: String { engine.modelID }

    public func embed(_ texts: [String]) async throws -> EmbeddingResponse {
        try await engine.embed(texts)
    }
}
