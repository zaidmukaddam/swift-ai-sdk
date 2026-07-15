import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct HuggingFaceModel: LanguageModel {
    public let provider = "huggingface"
    public let modelID: String

    private let engine: OpenAIModel

    public init(
        _ modelID: String,
        apiKey: String? = nil,
        baseURL: URL = URL(string: "https://router.huggingface.co/v1")!,
        headers: [String: String] = [:],
        urlSession: URLSession = .shared
    ) {
        self.modelID = modelID
        self.engine = OpenAIModel(
            modelID,
            apiKey: apiKey ?? ProcessInfo.processInfo.environment["HUGGINGFACE_API_KEY"] ?? "",
            baseURL: baseURL,
            headers: headers,
            urlSession: urlSession
        )
    }

    public func stream(
        _ request: LanguageModelRequest
    ) async throws -> AsyncThrowingStream<StreamPart, Error> {
        try await engine.stream(request)
    }
}
