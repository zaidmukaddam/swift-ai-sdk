import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct ProdiaImageModel: ImageModel {
    public let provider = "prodia"
    public let modelID: String

    private let apiKey: String
    private let baseURL: URL
    private let accept: String
    private let headers: [String: String]
    private let urlSession: URLSession

    public init(
        _ modelID: String = "inference.flux.schnell.txt2img.v2",
        apiKey: String? = nil,
        accept: String = "image/jpeg",
        baseURL: URL = URL(string: "https://inference.prodia.com/v2")!,
        headers: [String: String] = [:],
        urlSession: URLSession = .shared
    ) {
        self.modelID = modelID
        self.apiKey = apiKey ?? ProcessInfo.processInfo.environment["PRODIA_TOKEN"] ?? ""
        self.accept = accept
        self.baseURL = baseURL
        self.headers = headers
        self.urlSession = urlSession
    }

    public func generateImages(_ request: ImageModelRequest) async throws -> ImageModelResponse {
        var images: [Data] = []
        for _ in 0..<max(request.n, 1) {
            let (data, response) = try await urlSession.data(for: try buildURLRequest(request))
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                throw AIError.http(status: http.statusCode, body: String(decoding: data, as: UTF8.self))
            }
            images.append(data)
        }
        return ImageModelResponse(images: images)
    }

    func buildURLRequest(_ request: ImageModelRequest) throws -> URLRequest {
        var config: [String: JSONValue] = ["prompt": .string(request.prompt)]
        if let seed = request.seed { config["seed"] = .number(Double(seed)) }
        if let options = request.providerOptions?["prodia"]?.objectValue {
            for (key, value) in options { config[key] = value }
        }
        let body: JSONValue = .object([
            "type": .string(modelID),
            "config": .object(config)
        ])

        var urlRequest = URLRequest(url: baseURL.appendingPathComponent("job"))
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue("application/json", forHTTPHeaderField: "content-type")
        urlRequest.setValue(accept, forHTTPHeaderField: "Accept")
        for (field, value) in headers { urlRequest.setValue(value, forHTTPHeaderField: field) }
        urlRequest.httpBody = try JSONEncoder().encode(body)
        return urlRequest
    }
}

public struct QuiverAIImageModel: ImageModel {
    public let provider = "quiverai"
    public let modelID: String

    private let apiKey: String
    private let baseURL: URL
    private let headers: [String: String]
    private let urlSession: URLSession

    public init(
        _ modelID: String = "arrow-1.1",
        apiKey: String? = nil,
        baseURL: URL = URL(string: "https://api.quiver.ai/v1")!,
        headers: [String: String] = [:],
        urlSession: URLSession = .shared
    ) {
        self.modelID = modelID
        self.apiKey = apiKey ?? ProcessInfo.processInfo.environment["QUIVERAI_API_KEY"] ?? ""
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
            if let svg = item["svg"]?.stringValue {
                images.append(Data(svg.utf8))
            } else if let urlString = item["url"]?.stringValue, let url = URL(string: urlString) {
                let (bytes, _) = try await urlSession.data(from: url)
                images.append(bytes)
            }
        }
        guard !images.isEmpty else { throw AIError.decoding("QuiverAI returned no images") }
        return ImageModelResponse(images: images)
    }

    func buildURLRequest(_ request: ImageModelRequest) throws -> URLRequest {
        var body: [String: JSONValue] = [
            "model": .string(modelID),
            "prompt": .string(request.prompt)
        ]
        if let options = request.providerOptions?["quiverai"]?.objectValue {
            for (key, value) in options { body[key] = value }
        }

        var urlRequest = URLRequest(url: baseURL.appendingPathComponent("svgs/generations"))
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue("application/json", forHTTPHeaderField: "content-type")
        for (field, value) in headers { urlRequest.setValue(value, forHTTPHeaderField: field) }
        urlRequest.httpBody = try JSONEncoder().encode(JSONValue.object(body))
        return urlRequest
    }
}
