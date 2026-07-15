import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

private let alibabaConfiguration = OpenAICompatibleServiceConfiguration(
    providerName: "alibaba",
    baseURL: URL(string: "https://dashscope-intl.aliyuncs.com/compatible-mode/v1")!,
    apiKeyEnvironmentVariable: "ALIBABA_API_KEY"
)

public struct AlibabaModel: OpenAICompatibleLanguageModel {
    static let configuration = alibabaConfiguration
    let engine: OpenAIChatModel

    public init(
        _ modelID: String, apiKey: String? = nil, baseURL: URL? = nil,
        headers: [String: String] = [:], queryParams: [String: String] = [:],
        urlSession: URLSession = .shared
    ) {
        engine = alibabaConfiguration.makeModel(
            modelID, apiKey: apiKey, baseURL: baseURL, headers: headers,
            queryParams: queryParams, urlSession: urlSession
        )
    }
}

public struct AlibabaEmbeddingModel: EmbeddingModel {
    public let provider = "alibaba"
    public let modelID: String

    private let apiKey: String
    private let baseURL: URL
    private let dimension: Int?
    private let headers: [String: String]
    private let urlSession: URLSession

    static let maxTextsPerCall = 10

    public init(
        _ modelID: String = "text-embedding-v4",
        apiKey: String? = nil,
        baseURL: URL = URL(string: "https://dashscope-intl.aliyuncs.com/api/v1")!,
        dimension: Int? = nil,
        headers: [String: String] = [:],
        urlSession: URLSession = .shared
    ) {
        self.modelID = modelID
        self.apiKey = apiKey ?? ProcessInfo.processInfo.environment["ALIBABA_API_KEY"] ?? ""
        self.baseURL = baseURL
        self.dimension = dimension
        self.headers = headers
        self.urlSession = urlSession
    }

    public func embed(_ texts: [String]) async throws -> EmbeddingResponse {
        var embeddings: [[Double]] = []
        var usage = Usage()
        for start in stride(from: 0, to: texts.count, by: Self.maxTextsPerCall) {
            let batch = Array(texts[start..<min(start + Self.maxTextsPerCall, texts.count)])
            let (data, response) = try await urlSession.data(for: try buildURLRequest(batch))
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                throw AIError.http(status: http.statusCode, body: String(decoding: data, as: UTF8.self))
            }
            let decoded = try JSONDecoder().decode(JSONValue.self, from: data)
            let sorted = (decoded["output"]?["embeddings"]?.arrayValue ?? []).sorted {
                ($0["text_index"]?.intValue ?? 0) < ($1["text_index"]?.intValue ?? 0)
            }
            embeddings += sorted.map { ($0["embedding"]?.arrayValue ?? []).compactMap(\.doubleValue) }
            usage = usage + Usage(inputTokens: decoded["usage"]?["total_tokens"]?.intValue ?? 0)
        }
        return EmbeddingResponse(embeddings: embeddings, usage: usage)
    }

    func buildURLRequest(_ texts: [String]) throws -> URLRequest {
        var parameters: [String: JSONValue] = [:]
        if let dimension { parameters["dimension"] = .number(Double(dimension)) }
        let body: JSONValue = .object([
            "model": .string(modelID),
            "input": .object(["texts": .array(texts.map { .string($0) })]),
            "parameters": .object(parameters)
        ])

        var urlRequest = URLRequest(
            url: baseURL.appendingPathComponent("services/embeddings/text-embedding/text-embedding")
        )
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue("application/json", forHTTPHeaderField: "content-type")
        for (field, value) in headers { urlRequest.setValue(value, forHTTPHeaderField: field) }
        urlRequest.httpBody = try JSONEncoder().encode(body)
        return urlRequest
    }
}

public struct AlibabaVideoModel: VideoModel {
    public let provider = "alibaba"
    public let modelID: String

    private let apiKey: String
    private let baseURL: URL
    private let headers: [String: String]
    private let urlSession: URLSession
    private let pollInterval: TimeInterval
    private let pollTimeout: TimeInterval

    public init(
        _ modelID: String = "wan2.6-t2v",
        apiKey: String? = nil,
        baseURL: URL = URL(string: "https://dashscope-intl.aliyuncs.com")!,
        headers: [String: String] = [:],
        pollInterval: TimeInterval = 5,
        pollTimeout: TimeInterval = 600,
        urlSession: URLSession = .shared
    ) {
        self.modelID = modelID
        self.apiKey = apiKey ?? ProcessInfo.processInfo.environment["ALIBABA_API_KEY"] ?? ""
        self.baseURL = baseURL
        self.headers = headers
        self.pollInterval = pollInterval
        self.pollTimeout = pollTimeout
        self.urlSession = urlSession
    }

    public func generateVideos(_ request: VideoModelRequest) async throws -> VideoModelResponse {
        let (createData, createResponse) = try await urlSession.data(for: try buildCreateRequest(request))
        if let http = createResponse as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw AIError.http(status: http.statusCode, body: String(decoding: createData, as: UTF8.self))
        }
        let created = try JSONDecoder().decode(JSONValue.self, from: createData)
        guard let taskID = created["output"]?["task_id"]?.stringValue else {
            throw AIError.decoding("Alibaba returned no task_id")
        }

        let deadline = Date().addingTimeInterval(pollTimeout)
        while true {
            try await Task.sleep(nanoseconds: pollNanoseconds(pollInterval))
            if Date() > deadline { throw AIError.transport("Alibaba video generation timed out") }
            var poll = URLRequest(url: baseURL.appendingPathComponent("api/v1/tasks/\(taskID)"))
            poll.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            for (field, value) in headers { poll.setValue(value, forHTTPHeaderField: field) }
            let (pollData, _) = try await urlSession.data(for: poll)
            let status = try JSONDecoder().decode(JSONValue.self, from: pollData)
            switch status["output"]?["task_status"]?.stringValue {
            case "SUCCEEDED":
                guard let urlString = status["output"]?["video_url"]?.stringValue,
                      let url = URL(string: urlString)
                else { throw AIError.decoding("Alibaba finished without a video URL") }
                return VideoModelResponse(urls: [url], mediaType: "video/mp4")
            case "FAILED", "CANCELED":
                throw AIError.transport(
                    "Alibaba video generation failed: \(status["output"]?["message"]?.stringValue ?? "unknown")"
                )
            default:
                continue
            }
        }
    }

    func buildCreateRequest(_ request: VideoModelRequest) throws -> URLRequest {
        var input: [String: JSONValue] = ["prompt": .string(request.prompt)]
        if let image = request.image {
            if let data = image.data {
                input["img_url"] = .string("data:\(image.resolvedMediaType);base64,\(data.base64EncodedString())")
            } else if let url = image.url {
                input["img_url"] = .string(url.absoluteString)
            }
        }
        var parameters: [String: JSONValue] = [:]
        if let duration = request.duration { parameters["duration"] = .number(Double(duration)) }
        if case .object(let options)? = request.providerOptions,
           case .object(let alibaba)? = options["alibaba"] {
            for (key, value) in alibaba { parameters[key] = value }
        }

        var urlRequest = URLRequest(
            url: baseURL.appendingPathComponent("api/v1/services/aigc/video-generation/video-synthesis")
        )
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue("enable", forHTTPHeaderField: "X-DashScope-Async")
        urlRequest.setValue("application/json", forHTTPHeaderField: "content-type")
        for (field, value) in headers { urlRequest.setValue(value, forHTTPHeaderField: field) }
        urlRequest.httpBody = try JSONEncoder().encode(JSONValue.object([
            "model": .string(modelID),
            "input": .object(input),
            "parameters": .object(parameters)
        ]))
        return urlRequest
    }
}
