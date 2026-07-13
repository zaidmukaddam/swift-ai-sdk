import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct OpenAIImageModel: ImageModel {
    public let provider: String
    public let modelID: String

    private let apiKey: String
    private let baseURL: URL
    private let headers: [String: String]
    private let urlSession: URLSession

    public init(
        _ modelID: String,
        apiKey: String? = nil,
        baseURL: URL = URL(string: "https://api.openai.com/v1")!,
        headers: [String: String] = [:],
        urlSession: URLSession = .shared
    ) {
        self.init(
            modelID,
            apiKey: apiKey ?? ProcessInfo.processInfo.environment["OPENAI_API_KEY"] ?? "",
            baseURL: baseURL,
            headers: headers,
            urlSession: urlSession,
            providerName: "openai"
        )
    }

    init(
        _ modelID: String,
        apiKey: String,
        baseURL: URL,
        headers: [String: String],
        urlSession: URLSession,
        providerName: String
    ) {
        self.modelID = modelID
        self.apiKey = apiKey
        self.baseURL = baseURL
        self.headers = headers
        self.urlSession = urlSession
        self.provider = providerName
    }

    public func generateImages(_ request: ImageModelRequest) async throws -> ImageModelResponse {
        let urlRequest = try buildURLRequest(request)
        let (data, response) = try await urlSession.data(for: urlRequest)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw AIError.http(status: http.statusCode, body: String(decoding: data, as: UTF8.self))
        }

        let decoded = try JSONDecoder().decode(ImagesResponseBody.self, from: data)
        let images = try decoded.data.map { item in
            guard let bytes = Data(base64Encoded: item.b64_json) else {
                throw AIError.decoding("Image payload was not valid base64")
            }
            return bytes
        }
        return ImageModelResponse(
            images: images,
            revisedPrompts: decoded.data.map(\.revised_prompt)
        )
    }

    func buildURLRequest(_ request: ImageModelRequest) throws -> URLRequest {
        if !request.images.isEmpty {
            return try buildEditRequest(request)
        }
        var body: [String: JSONValue] = [
            "model": .string(modelID),
            "prompt": .string(request.prompt),
            "n": .number(Double(request.n))
        ]
        if let size = request.size {
            body["size"] = .string(size)
        }
        if !Self.hasDefaultBase64ResponseFormat(modelID) {
            body["response_format"] = .string("b64_json")
        }
        if let options = request.providerOptions?["openai"]?.objectValue {
            for (key, value) in options {
                body[key] = value
            }
        }

        var urlRequest = URLRequest(url: baseURL.appendingPathComponent("images/generations"))
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

    private func buildEditRequest(_ request: ImageModelRequest) throws -> URLRequest {
        let boundary = "swift-ai-sdk-\(request.prompt.hashValue.magnitude)"
        var form = MultipartForm(boundary: boundary)
        form.addField(name: "model", value: modelID)
        form.addField(name: "prompt", value: request.prompt)
        form.addField(name: "n", value: String(request.n))
        if let size = request.size { form.addField(name: "size", value: size) }
        if !Self.hasDefaultBase64ResponseFormat(modelID) {
            form.addField(name: "response_format", value: "b64_json")
        }
        if let options = request.providerOptions?["openai"]?.objectValue {
            for (key, value) in options {
                form.addField(name: key, value: value.stringValue ?? "\(value)")
            }
        }
        for (index, image) in request.images.enumerated() {
            guard let data = image.data else {
                throw AIError.invalidRequest(
                    "OpenAI image edits need inline bytes; URL images are not supported"
                )
            }
            form.addFile(
                name: "image[]",
                filename: "image-\(index).png",
                mediaType: image.resolvedMediaType,
                data: data
            )
        }

        var urlRequest = URLRequest(url: baseURL.appendingPathComponent("images/edits"))
        urlRequest.httpMethod = "POST"
        if !apiKey.isEmpty {
            urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        urlRequest.setValue(
            "multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "content-type"
        )
        for (field, value) in headers {
            urlRequest.setValue(value, forHTTPHeaderField: field)
        }
        urlRequest.httpBody = form.finish()
        return urlRequest
    }

    static func hasDefaultBase64ResponseFormat(_ modelID: String) -> Bool {
        let prefixes = ["chatgpt-image-", "gpt-image-1-mini", "gpt-image-1.5", "gpt-image-1", "gpt-image-2"]
        return prefixes.contains { modelID.hasPrefix($0) }
    }
}

private struct ImagesResponseBody: Decodable {
    var data: [Item]

    struct Item: Decodable {
        var b64_json: String
        var revised_prompt: String?
    }
}
