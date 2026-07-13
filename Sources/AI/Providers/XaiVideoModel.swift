import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct XaiVideoModel: VideoModel {
    public let provider = "xai"
    public let modelID: String

    private let apiKey: String
    private let baseURL: URL
    private let headers: [String: String]
    private let urlSession: URLSession
    private let pollInterval: TimeInterval
    private let pollTimeout: TimeInterval

    public init(
        _ modelID: String,
        apiKey: String? = nil,
        baseURL: URL = URL(string: "https://api.x.ai/v1")!,
        headers: [String: String] = [:],
        pollInterval: TimeInterval = 5,
        pollTimeout: TimeInterval = 600,
        urlSession: URLSession = .shared
    ) {
        self.modelID = modelID
        self.apiKey = apiKey ?? ProcessInfo.processInfo.environment["XAI_API_KEY"] ?? ""
        self.baseURL = baseURL
        self.headers = headers
        self.pollInterval = pollInterval
        self.pollTimeout = pollTimeout
        self.urlSession = urlSession
    }

    public func generateVideos(_ request: VideoModelRequest) async throws -> VideoModelResponse {
        let (createData, createResponse) = try await urlSession.data(
            for: try buildCreateRequest(request)
        )
        if let http = createResponse as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw AIError.http(
                status: http.statusCode, body: String(decoding: createData, as: UTF8.self)
            )
        }
        let created = try JSONDecoder().decode(JSONValue.self, from: createData)
        guard let requestID = created["request_id"]?.stringValue else {
            throw AIError.decoding("xAI returned no request_id for the video job")
        }

        let deadline = Date().addingTimeInterval(pollTimeout)
        while true {
            try await Task.sleep(nanoseconds: UInt64(pollInterval * 1_000_000_000))
            if Date() > deadline {
                throw AIError.transport("xAI video generation timed out after \(Int(pollTimeout))s")
            }

            let (statusData, statusResponse) = try await urlSession.data(
                for: buildStatusRequest(requestID: requestID)
            )
            if let http = statusResponse as? HTTPURLResponse,
               !(200..<300).contains(http.statusCode) {
                throw AIError.http(
                    status: http.statusCode, body: String(decoding: statusData, as: UTF8.self)
                )
            }
            let status = try JSONDecoder().decode(JSONValue.self, from: statusData)
            if let terminal = try Self.resolvePoll(status) {
                return terminal
            }
        }
    }

    static func resolvePoll(_ status: JSONValue) throws -> VideoModelResponse? {
        let state = status["status"]?.stringValue
        let videoURL = status["video"]?["url"]?.stringValue

        if state == "done" || (state == nil && videoURL != nil) {
            if status["video"]?["respect_moderation"]?.boolValue == false {
                throw AIError.transport(
                    "xAI video generation was blocked by a content policy violation"
                )
            }
            guard let videoURL, let url = URL(string: videoURL) else {
                throw AIError.decoding("xAI video job finished without a video URL")
            }
            return VideoModelResponse(urls: [url], mediaType: "video/mp4")
        }
        if state == "failed" {
            throw AIError.transport("xAI video generation failed")
        }
        if state == "expired" {
            throw AIError.transport("xAI video generation request expired")
        }
        return nil
    }

    func buildCreateRequest(_ request: VideoModelRequest) throws -> URLRequest {
        var body: [String: JSONValue] = [
            "model": .string(modelID),
            "prompt": .string(request.prompt)
        ]
        if let duration = request.duration { body["duration"] = .number(Double(duration)) }
        if let aspectRatio = request.aspectRatio { body["aspect_ratio"] = .string(aspectRatio) }
        if let image = request.image {
            let url: String
            if let data = image.data {
                url = "data:\(image.resolvedMediaType);base64,\(data.base64EncodedString())"
            } else if let remote = image.url {
                url = remote.absoluteString
            } else {
                url = ""
            }
            if !url.isEmpty { body["image"] = .object(["url": .string(url)]) }
        }
        if case .object(let options)? = request.providerOptions {
            for (key, value) in options { body[key] = value }
        }

        var urlRequest = URLRequest(url: baseURL.appendingPathComponent("videos/generations"))
        urlRequest.httpMethod = "POST"
        if !apiKey.isEmpty {
            urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        urlRequest.setValue("application/json", forHTTPHeaderField: "content-type")
        for (field, value) in headers {
            urlRequest.setValue(value, forHTTPHeaderField: field)
        }
        urlRequest.httpBody = try JSONEncoder().encode(JSONValue.object(body))
        return urlRequest
    }

    func buildStatusRequest(requestID: String) -> URLRequest {
        var urlRequest = URLRequest(url: baseURL.appendingPathComponent("videos/\(requestID)"))
        urlRequest.httpMethod = "GET"
        if !apiKey.isEmpty {
            urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        for (field, value) in headers {
            urlRequest.setValue(value, forHTTPHeaderField: field)
        }
        return urlRequest
    }
}
