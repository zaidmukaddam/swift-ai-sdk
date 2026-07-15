import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct ByteDanceImageModel: ImageModel {
    public let provider = "bytedance"
    public let modelID: String

    private let apiKey: String
    private let baseURL: URL
    private let headers: [String: String]
    private let urlSession: URLSession

    public init(
        _ modelID: String = "seedream-4-0-250828",
        apiKey: String? = nil,
        baseURL: URL = URL(string: "https://ark.ap-southeast.bytepluses.com/api/v3")!,
        headers: [String: String] = [:],
        urlSession: URLSession = .shared
    ) {
        self.modelID = modelID
        self.apiKey = apiKey ?? ProcessInfo.processInfo.environment["ARK_API_KEY"] ?? ""
        self.baseURL = baseURL
        self.headers = headers
        self.urlSession = urlSession
    }

    public func generateImages(_ request: ImageModelRequest) async throws -> ImageModelResponse {
        let (data, response) = try await urlSession.data(for: try buildURLRequest(request))
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw AIError.http(status: http.statusCode, body: String(decoding: data, as: UTF8.self))
        }
        let decoded = try JSONDecoder().decode(JSONValue.self, from: data)
        var images: [Data] = []
        for item in decoded["data"]?.arrayValue ?? [] {
            if let base64 = item["b64_json"]?.stringValue, let bytes = Data(base64Encoded: base64) {
                images.append(bytes)
            } else if let urlString = item["url"]?.stringValue, let url = URL(string: urlString) {
                let (bytes, _) = try await urlSession.data(from: url)
                images.append(bytes)
            }
        }
        guard !images.isEmpty else { throw AIError.decoding("ByteDance returned no images") }
        return ImageModelResponse(images: images)
    }

    func buildURLRequest(_ request: ImageModelRequest) throws -> URLRequest {
        var body: [String: JSONValue] = [
            "model": .string(modelID),
            "prompt": .string(request.prompt),
            "response_format": .string("url")
        ]
        if let size = request.size { body["size"] = .string(size) }
        if let seed = request.seed { body["seed"] = .number(Double(seed)) }
        if let options = request.providerOptions?["bytedance"]?.objectValue {
            for (key, value) in options { body[key] = value }
        }

        var urlRequest = URLRequest(url: baseURL.appendingPathComponent("images/generations"))
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue("application/json", forHTTPHeaderField: "content-type")
        for (field, value) in headers { urlRequest.setValue(value, forHTTPHeaderField: field) }
        urlRequest.httpBody = try JSONEncoder().encode(JSONValue.object(body))
        return urlRequest
    }
}

public struct ByteDanceVideoModel: VideoModel {
    public let provider = "bytedance"
    public let modelID: String

    private let apiKey: String
    private let baseURL: URL
    private let headers: [String: String]
    private let urlSession: URLSession
    private let pollInterval: TimeInterval
    private let pollTimeout: TimeInterval

    public init(
        _ modelID: String = "seedance-1-0-pro-250528",
        apiKey: String? = nil,
        baseURL: URL = URL(string: "https://ark.ap-southeast.bytepluses.com/api/v3")!,
        headers: [String: String] = [:],
        pollInterval: TimeInterval = 5,
        pollTimeout: TimeInterval = 600,
        urlSession: URLSession = .shared
    ) {
        self.modelID = modelID
        self.apiKey = apiKey ?? ProcessInfo.processInfo.environment["ARK_API_KEY"] ?? ""
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
        guard let taskID = created["id"]?.stringValue else {
            throw AIError.decoding("ByteDance returned no task id")
        }

        let deadline = Date().addingTimeInterval(pollTimeout)
        while true {
            try await Task.sleep(nanoseconds: pollNanoseconds(pollInterval))
            if Date() > deadline { throw AIError.transport("ByteDance video generation timed out") }
            var poll = URLRequest(
                url: baseURL.appendingPathComponent("contents/generations/tasks/\(taskID)")
            )
            poll.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            for (field, value) in headers { poll.setValue(value, forHTTPHeaderField: field) }
            let (pollData, _) = try await urlSession.data(for: poll)
            let status = try JSONDecoder().decode(JSONValue.self, from: pollData)
            switch status["status"]?.stringValue {
            case "succeeded":
                guard let urlString = status["content"]?["video_url"]?.stringValue,
                      let url = URL(string: urlString)
                else { throw AIError.decoding("ByteDance finished without a video URL") }
                return VideoModelResponse(urls: [url], mediaType: "video/mp4")
            case "failed", "cancelled":
                throw AIError.transport(
                    "ByteDance video generation failed: \(status["error"]?["message"]?.stringValue ?? "unknown")"
                )
            default:
                continue
            }
        }
    }

    func buildCreateRequest(_ request: VideoModelRequest) throws -> URLRequest {
        var content: [JSONValue] = [.object(["type": "text", "text": .string(request.prompt)])]
        if let image = request.image {
            let url: String?
            if let data = image.data {
                url = "data:\(image.resolvedMediaType);base64,\(data.base64EncodedString())"
            } else if let remote = image.url {
                url = remote.absoluteString
            } else {
                url = nil
            }
            if let url {
                content.append(.object([
                    "type": "image_url", "image_url": .object(["url": .string(url)])
                ]))
            }
        }
        var body: [String: JSONValue] = [
            "model": .string(modelID),
            "content": .array(content)
        ]
        if let options = request.providerOptions?["bytedance"]?.objectValue {
            for (key, value) in options { body[key] = value }
        }

        var urlRequest = URLRequest(url: baseURL.appendingPathComponent("contents/generations/tasks"))
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue("application/json", forHTTPHeaderField: "content-type")
        for (field, value) in headers { urlRequest.setValue(value, forHTTPHeaderField: field) }
        urlRequest.httpBody = try JSONEncoder().encode(JSONValue.object(body))
        return urlRequest
    }
}
