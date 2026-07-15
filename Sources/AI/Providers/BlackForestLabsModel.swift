import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct BlackForestLabsImageModel: ImageModel {
    public let provider = "black-forest-labs"
    public let modelID: String

    private let apiKey: String
    private let baseURL: URL
    private let headers: [String: String]
    private let urlSession: URLSession
    private let pollInterval: TimeInterval
    private let pollTimeout: TimeInterval

    public init(
        _ modelID: String = "flux-pro-1.1",
        apiKey: String? = nil,
        baseURL: URL = URL(string: "https://api.bfl.ai/v1")!,
        headers: [String: String] = [:],
        pollInterval: TimeInterval = 1,
        pollTimeout: TimeInterval = 300,
        urlSession: URLSession = .shared
    ) {
        self.modelID = modelID
        self.apiKey = apiKey ?? ProcessInfo.processInfo.environment["BFL_API_KEY"] ?? ""
        self.baseURL = baseURL
        self.headers = headers
        self.pollInterval = pollInterval
        self.pollTimeout = pollTimeout
        self.urlSession = urlSession
    }

    public func generateImages(_ request: ImageModelRequest) async throws -> ImageModelResponse {
        var images: [Data] = []
        for _ in 0..<max(request.n, 1) {
            images.append(try await generateOne(request))
        }
        return ImageModelResponse(images: images)
    }

    private func generateOne(_ request: ImageModelRequest) async throws -> Data {
        let (createData, createResponse) = try await urlSession.data(for: try buildCreateRequest(request))
        if let http = createResponse as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw AIError.http(status: http.statusCode, body: String(decoding: createData, as: UTF8.self))
        }
        let created = try JSONDecoder().decode(JSONValue.self, from: createData)
        guard let pollURLString = created["polling_url"]?.stringValue,
              let pollURL = URL(string: pollURLString)
        else { throw AIError.decoding("Black Forest Labs returned no polling_url") }

        let deadline = Date().addingTimeInterval(pollTimeout)
        while true {
            try await Task.sleep(nanoseconds: pollNanoseconds(pollInterval))
            if Date() > deadline { throw AIError.transport("Black Forest Labs generation timed out") }
            var poll = URLRequest(url: pollURL)
            poll.setValue(apiKey, forHTTPHeaderField: "x-key")
            for (field, value) in headers { poll.setValue(value, forHTTPHeaderField: field) }
            let (pollData, _) = try await urlSession.data(for: poll)
            let status = try JSONDecoder().decode(JSONValue.self, from: pollData)
            switch status["status"]?.stringValue {
            case "Ready":
                guard let sample = status["result"]?["sample"]?.stringValue,
                      let sampleURL = URL(string: sample)
                else { throw AIError.decoding("Black Forest Labs finished without an image URL") }
                let (bytes, _) = try await urlSession.data(from: sampleURL)
                return bytes
            case "Error", "Failed", "Content Moderated", "Request Moderated":
                throw AIError.transport(
                    "Black Forest Labs generation failed: \(status["status"]?.stringValue ?? "unknown")"
                )
            default:
                continue
            }
        }
    }

    func buildCreateRequest(_ request: ImageModelRequest) throws -> URLRequest {
        var body: [String: JSONValue] = ["prompt": .string(request.prompt)]
        if let size = request.size {
            let parts = size.split(separator: "x")
            if parts.count == 2, let width = Int(parts[0]), let height = Int(parts[1]) {
                body["width"] = .number(Double(width))
                body["height"] = .number(Double(height))
            }
        }
        if let aspectRatio = request.aspectRatio { body["aspect_ratio"] = .string(aspectRatio) }
        if let seed = request.seed { body["seed"] = .number(Double(seed)) }
        if let options = request.providerOptions?["black-forest-labs"]?.objectValue {
            for (key, value) in options { body[key] = value }
        }

        var urlRequest = URLRequest(url: baseURL.appendingPathComponent(modelID))
        urlRequest.httpMethod = "POST"
        urlRequest.setValue(apiKey, forHTTPHeaderField: "x-key")
        urlRequest.setValue("application/json", forHTTPHeaderField: "content-type")
        for (field, value) in headers { urlRequest.setValue(value, forHTTPHeaderField: field) }
        urlRequest.httpBody = try JSONEncoder().encode(JSONValue.object(body))
        return urlRequest
    }
}
