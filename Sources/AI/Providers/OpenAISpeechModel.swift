import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct OpenAISpeechModel: SpeechModel {
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

    public func generateSpeech(_ request: SpeechModelRequest) async throws -> SpeechModelResponse {
        let urlRequest = try buildURLRequest(request)
        let (data, response) = try await urlSession.data(for: urlRequest)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw AIError.http(status: http.statusCode, body: String(decoding: data, as: UTF8.self))
        }
        let format = Self.resolvedFormat(request.outputFormat)
        return SpeechModelResponse(audio: data, mediaType: Self.mediaType(forFormat: format))
    }

    func buildURLRequest(_ request: SpeechModelRequest) throws -> URLRequest {
        var body: [String: JSONValue] = [
            "model": .string(modelID),
            "input": .string(request.text),
            "voice": .string(request.voice ?? "alloy"),
            "response_format": .string(Self.resolvedFormat(request.outputFormat))
        ]
        if let speed = request.speed {
            body["speed"] = .number(speed)
        }
        if let instructions = request.instructions {
            body["instructions"] = .string(instructions)
        }
        if let options = request.providerOptions?["openai"]?.objectValue {
            for (key, value) in options {
                body[key] = value
            }
        }

        var urlRequest = URLRequest(url: baseURL.appendingPathComponent("audio/speech"))
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

    static func resolvedFormat(_ outputFormat: String?) -> String {
        let supported = ["mp3", "opus", "aac", "flac", "wav", "pcm"]
        if let format = outputFormat, supported.contains(format) {
            return format
        }
        return "mp3"
    }

    static func mediaType(forFormat format: String) -> String {
        switch format {
        case "mp3": return "audio/mpeg"
        case "opus": return "audio/ogg"
        case "aac": return "audio/aac"
        case "flac": return "audio/flac"
        case "wav": return "audio/wav"
        case "pcm": return "audio/pcm"
        default: return "audio/mpeg"
        }
    }
}
