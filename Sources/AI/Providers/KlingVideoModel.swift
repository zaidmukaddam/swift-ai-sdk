import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
#if canImport(CryptoKit)
import CryptoKit
#endif

public struct KlingVideoModel: VideoModel {
    public let provider = "klingai"
    public let modelID: String

    private let accessKey: String
    private let secretKey: String
    private let baseURL: URL
    private let headers: [String: String]
    private let urlSession: URLSession
    private let pollInterval: TimeInterval
    private let pollTimeout: TimeInterval

    public init(
        _ modelID: String = "kling-v2-master",
        accessKey: String? = nil,
        secretKey: String? = nil,
        baseURL: URL = URL(string: "https://api-singapore.klingai.com")!,
        headers: [String: String] = [:],
        pollInterval: TimeInterval = 5,
        pollTimeout: TimeInterval = 600,
        urlSession: URLSession = .shared
    ) {
        self.modelID = modelID
        self.accessKey = accessKey ?? ProcessInfo.processInfo.environment["KLING_ACCESS_KEY"] ?? ""
        self.secretKey = secretKey ?? ProcessInfo.processInfo.environment["KLING_SECRET_KEY"] ?? ""
        self.baseURL = baseURL
        self.headers = headers
        self.pollInterval = pollInterval
        self.pollTimeout = pollTimeout
        self.urlSession = urlSession
    }

    static func route(
        _ modelID: String, hasImage: Bool
    ) -> (endpoint: String, apiModelName: String) {
        let suffixes: [(String, String)] = [
            ("-motion-control", "motion-control"),
            ("-t2v", "text2video"),
            ("-i2v", "image2video")
        ]
        for (suffix, endpoint) in suffixes where modelID.hasSuffix(suffix) {
            return (endpoint, apiModelName(String(modelID.dropLast(suffix.count))))
        }
        return (hasImage ? "image2video" : "text2video", apiModelName(modelID))
    }

    static func apiModelName(_ base: String) -> String {
        var name = base
        if name.hasSuffix(".0") { name = String(name.dropLast(2)) }
        return name.replacingOccurrences(of: ".", with: "-")
    }

    public func generateVideos(_ request: VideoModelRequest) async throws -> VideoModelResponse {
        let route = Self.route(modelID, hasImage: request.image != nil)
        let endpoint = route.endpoint
        let (createData, createResponse) = try await urlSession.data(
            for: try buildCreateRequest(request, endpoint: endpoint, modelName: route.apiModelName)
        )
        if let http = createResponse as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw AIError.http(status: http.statusCode, body: String(decoding: createData, as: UTF8.self))
        }
        let created = try JSONDecoder().decode(JSONValue.self, from: createData)
        guard let taskID = created["data"]?["task_id"]?.stringValue else {
            throw AIError.decoding("Kling returned no task_id")
        }

        let deadline = Date().addingTimeInterval(pollTimeout)
        while true {
            try await Task.sleep(nanoseconds: pollNanoseconds(pollInterval))
            if Date() > deadline { throw AIError.transport("Kling video generation timed out") }
            var poll = URLRequest(
                url: baseURL.appendingPathComponent("v1/videos/\(endpoint)/\(taskID)")
            )
            poll.setValue("Bearer \(try authToken())", forHTTPHeaderField: "Authorization")
            for (field, value) in headers { poll.setValue(value, forHTTPHeaderField: field) }
            let (pollData, _) = try await urlSession.data(for: poll)
            let status = try JSONDecoder().decode(JSONValue.self, from: pollData)
            switch status["data"]?["task_status"]?.stringValue {
            case "succeed":
                guard let urlString = status["data"]?["task_result"]?["videos"]?
                    .arrayValue?.first?["url"]?.stringValue,
                      let url = URL(string: urlString)
                else { throw AIError.decoding("Kling finished without a video URL") }
                return VideoModelResponse(urls: [url], mediaType: "video/mp4")
            case "failed":
                throw AIError.transport(
                    "Kling video generation failed: \(status["data"]?["task_status_msg"]?.stringValue ?? "unknown")"
                )
            default:
                continue
            }
        }
    }

    func buildCreateRequest(
        _ request: VideoModelRequest, endpoint: String, modelName: String
    ) throws -> URLRequest {
        var body: [String: JSONValue] = [
            "model_name": .string(modelName),
            "prompt": .string(request.prompt)
        ]
        if let aspectRatio = request.aspectRatio { body["aspect_ratio"] = .string(aspectRatio) }
        if let duration = request.duration { body["duration"] = .string("\(duration)") }
        if let image = request.image {
            if let data = image.data {
                body["image"] = .string(data.base64EncodedString())
            } else if let url = image.url {
                body["image"] = .string(url.absoluteString)
            }
        }
        if let options = request.providerOptions?["klingai"]?.objectValue {
            for (key, value) in options { body[key] = value }
        }

        var urlRequest = URLRequest(url: baseURL.appendingPathComponent("v1/videos/\(endpoint)"))
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("Bearer \(try authToken())", forHTTPHeaderField: "Authorization")
        urlRequest.setValue("application/json", forHTTPHeaderField: "content-type")
        for (field, value) in headers { urlRequest.setValue(value, forHTTPHeaderField: field) }
        urlRequest.httpBody = try JSONEncoder().encode(JSONValue.object(body))
        return urlRequest
    }

    func authToken() throws -> String {
        let now = Int(Date().timeIntervalSince1970)
        let header = Self.base64URL(Data(#"{"alg":"HS256","typ":"JWT"}"#.utf8))
        let payload = Self.base64URL(Data(
            "{\"iss\":\"\(accessKey)\",\"exp\":\(now + 1800),\"nbf\":\(now - 5)}".utf8
        ))
        let signingInput = "\(header).\(payload)"
        return "\(signingInput).\(try Self.sign(signingInput, secret: secretKey))"
    }

    static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    static func sign(_ input: String, secret: String) throws -> String {
        #if canImport(CryptoKit)
        let mac = HMAC<SHA256>.authenticationCode(
            for: Data(input.utf8), using: SymmetricKey(data: Data(secret.utf8))
        )
        return base64URL(Data(mac))
        #else
        throw AIError.invalidRequest("Kling video generation requires CryptoKit for JWT signing")
        #endif
    }
}
