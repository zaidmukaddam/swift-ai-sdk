import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct XaiImageModel: ImageModel {
    public let provider = "xai"
    public let modelID: String

    private let apiKey: String
    private let baseURL: URL
    private let headers: [String: String]
    private let urlSession: URLSession

    public init(
        _ modelID: String = "grok-2-image",
        apiKey: String? = nil,
        baseURL: URL = URL(string: "https://api.x.ai/v1")!,
        headers: [String: String] = [:],
        urlSession: URLSession = .shared
    ) {
        self.modelID = modelID
        self.apiKey = apiKey ?? ProcessInfo.processInfo.environment["XAI_API_KEY"] ?? ""
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
        let items = decoded["data"]?.arrayValue ?? []
        var images: [Data] = []
        for item in items {
            if let base64 = item["b64_json"]?.stringValue, let bytes = Data(base64Encoded: base64) {
                images.append(bytes)
            } else if let urlString = item["url"]?.stringValue, let url = URL(string: urlString) {
                let (bytes, _) = try await urlSession.data(from: url)
                images.append(bytes)
            }
        }
        guard !images.isEmpty else { throw AIError.decoding("xAI returned no images") }
        return ImageModelResponse(
            images: images,
            revisedPrompts: items.map { $0["revised_prompt"]?.stringValue }
        )
    }

    func buildURLRequest(_ request: ImageModelRequest) throws -> URLRequest {
        if !request.images.isEmpty {
            return try buildBody(request, path: "images/edits", includeInputImages: true)
        }
        return try buildBody(request, path: "images/generations", includeInputImages: false)
    }

    private func buildBody(
        _ request: ImageModelRequest, path: String, includeInputImages: Bool
    ) throws -> URLRequest {
        var body: [String: JSONValue] = [
            "model": .string(modelID),
            "prompt": .string(request.prompt),
            "n": .number(Double(request.n)),
            "response_format": .string("b64_json")
        ]
        if let aspectRatio = request.aspectRatio { body["aspect_ratio"] = .string(aspectRatio) }
        if let size = request.size { body["resolution"] = .string(size) }
        if let seed = request.seed { body["seed"] = .number(Double(seed)) }
        if includeInputImages {
            body["images"] = .array(try request.images.map { try Self.imageValue($0) })
        }
        if let options = request.providerOptions?["xai"]?.objectValue {
            for (key, value) in options { body[key] = value }
        }

        var urlRequest = URLRequest(url: baseURL.appendingPathComponent(path))
        urlRequest.httpMethod = "POST"
        if !apiKey.isEmpty {
            urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        urlRequest.setValue("application/json", forHTTPHeaderField: "content-type")
        for (field, value) in headers { urlRequest.setValue(value, forHTTPHeaderField: field) }
        urlRequest.httpBody = try JSONEncoder().encode(JSONValue.object(body))
        return urlRequest
    }

    static func imageValue(_ image: ImageContent) throws -> JSONValue {
        if let url = image.url {
            return .object(["url": .string(url.absoluteString)])
        }
        if let data = image.data {
            let dataURL = "data:\(image.resolvedMediaType);base64,\(data.base64EncodedString())"
            return .object(["url": .string(dataURL)])
        }
        throw AIError.invalidRequest("xAI image edits need an image URL or inline bytes")
    }
}
