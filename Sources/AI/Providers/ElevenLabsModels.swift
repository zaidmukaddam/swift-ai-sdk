import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct ElevenLabsSpeechModel: SpeechModel {
    public let provider = "elevenlabs"
    public let modelID: String

    private let apiKey: String
    private let baseURL: URL
    private let headers: [String: String]
    private let urlSession: URLSession

    public init(
        _ modelID: String,
        apiKey: String? = nil,
        baseURL: URL = URL(string: "https://api.elevenlabs.io")!,
        headers: [String: String] = [:],
        urlSession: URLSession = .shared
    ) {
        self.modelID = modelID
        self.apiKey = apiKey ?? ProcessInfo.processInfo.environment["ELEVENLABS_API_KEY"] ?? ""
        self.baseURL = baseURL
        self.headers = headers
        self.urlSession = urlSession
    }

    public func generateSpeech(_ request: SpeechModelRequest) async throws -> SpeechModelResponse {
        let (data, response) = try await urlSession.data(for: try buildURLRequest(request))
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw AIError.http(status: http.statusCode, body: String(decoding: data, as: UTF8.self))
        }
        return SpeechModelResponse(audio: data, mediaType: Self.mediaType(for: request.outputFormat))
    }

    func buildURLRequest(_ request: SpeechModelRequest) throws -> URLRequest {
        let requestedVoice = request.voice ?? ""
        let voice = requestedVoice.isEmpty ? "21m00Tcm4TlvDq8ikWAM" : requestedVoice
        // Percent-encode "/" too, so a voice id can't add or escape a path segment.
        guard let encodedVoice = voice.addingPercentEncoding(
            withAllowedCharacters: .urlPathAllowed.subtracting(CharacterSet(charactersIn: "/"))
        ), var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw AIError.invalidRequest("Invalid ElevenLabs voice id: \(voice)")
        }
        components.percentEncodedPath += "/v1/text-to-speech/\(encodedVoice)"
        if let outputFormat = request.outputFormat {
            components.queryItems = [URLQueryItem(
                name: "output_format", value: Self.qualifiedFormat(outputFormat)
            )]
        }

        var body: [String: JSONValue] = [
            "text": .string(request.text),
            "model_id": .string(modelID)
        ]
        if let instructions = request.instructions {
            body["next_text"] = .string(instructions)
        }
        if case .object(let options)? = request.providerOptions {
            for (key, value) in options { body[key] = value }
        }

        guard let url = components.url else {
            throw AIError.invalidRequest("Could not build ElevenLabs speech URL for voice \(voice)")
        }
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue(apiKey, forHTTPHeaderField: "xi-api-key")
        urlRequest.setValue("application/json", forHTTPHeaderField: "content-type")
        for (field, value) in headers { urlRequest.setValue(value, forHTTPHeaderField: field) }
        urlRequest.httpBody = try JSONEncoder().encode(JSONValue.object(body))
        return urlRequest
    }

    static func qualifiedFormat(_ short: String) -> String {
        switch short {
        case "mp3": "mp3_44100_128"
        case "mp3_32": "mp3_44100_32"
        case "mp3_64": "mp3_44100_64"
        case "mp3_96": "mp3_44100_96"
        case "mp3_128": "mp3_44100_128"
        case "mp3_192": "mp3_44100_192"
        case "pcm": "pcm_44100"
        default: short
        }
    }

    static func mediaType(for outputFormat: String?) -> String {
        let format = outputFormat ?? "mp3"
        if format.hasPrefix("pcm") { return "audio/pcm" }
        if format.hasPrefix("ulaw") { return "audio/basic" }
        if format.hasPrefix("opus") { return "audio/opus" }
        return "audio/mpeg"
    }
}

public struct ElevenLabsTranscriptionModel: TranscriptionModel {
    public let provider = "elevenlabs"
    public let modelID: String

    private let apiKey: String
    private let baseURL: URL
    private let headers: [String: String]
    private let urlSession: URLSession

    public init(
        _ modelID: String = "scribe_v2",
        apiKey: String? = nil,
        baseURL: URL = URL(string: "https://api.elevenlabs.io")!,
        headers: [String: String] = [:],
        urlSession: URLSession = .shared
    ) {
        self.modelID = modelID
        self.apiKey = apiKey ?? ProcessInfo.processInfo.environment["ELEVENLABS_API_KEY"] ?? ""
        self.baseURL = baseURL
        self.headers = headers
        self.urlSession = urlSession
    }

    public func transcribe(_ request: TranscriptionModelRequest) async throws -> TranscriptionModelResponse {
        let (data, response) = try await urlSession.data(for: buildURLRequest(request))
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw AIError.http(status: http.statusCode, body: String(decoding: data, as: UTF8.self))
        }
        let decoded = try JSONDecoder().decode(JSONValue.self, from: data)
        let words = decoded["words"]?.arrayValue ?? []
        return TranscriptionModelResponse(
            text: decoded["text"]?.stringValue ?? "",
            segments: words.compactMap { word in
                guard let text = word["text"]?.stringValue else { return nil }
                return TranscriptionSegment(
                    text: text,
                    startSecond: word["start"]?.doubleValue ?? 0,
                    endSecond: word["end"]?.doubleValue ?? 0
                )
            },
            language: decoded["language_code"]?.stringValue,
            durationInSeconds: nil
        )
    }

    func buildURLRequest(_ request: TranscriptionModelRequest) -> URLRequest {
        var form = MultipartForm(boundary: "swift-ai-sdk-\(modelID.hashValue.magnitude)")
        form.addField(name: "model_id", value: modelID)
        form.addFile(
            name: "file", filename: "audio",
            mediaType: request.mediaType, data: request.audio
        )

        var urlRequest = URLRequest(url: baseURL.appendingPathComponent("v1/speech-to-text"))
        urlRequest.httpMethod = "POST"
        urlRequest.setValue(apiKey, forHTTPHeaderField: "xi-api-key")
        urlRequest.setValue(
            "multipart/form-data; boundary=\(form.boundary)", forHTTPHeaderField: "content-type"
        )
        for (field, value) in headers { urlRequest.setValue(value, forHTTPHeaderField: field) }
        urlRequest.httpBody = form.finish()
        return urlRequest
    }
}
