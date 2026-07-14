import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct LMNTSpeechModel: SpeechModel {
    public let provider = "lmnt"
    public let modelID: String

    private let apiKey: String
    private let baseURL: URL
    private let headers: [String: String]
    private let urlSession: URLSession

    public init(
        _ modelID: String = "blizzard",
        apiKey: String? = nil,
        baseURL: URL = URL(string: "https://api.lmnt.com")!,
        headers: [String: String] = [:],
        urlSession: URLSession = .shared
    ) {
        self.modelID = modelID
        self.apiKey = apiKey ?? ProcessInfo.processInfo.environment["LMNT_API_KEY"] ?? ""
        self.baseURL = baseURL
        self.headers = headers
        self.urlSession = urlSession
    }

    public func generateSpeech(_ request: SpeechModelRequest) async throws -> SpeechModelResponse {
        let (data, response) = try await urlSession.data(for: try buildURLRequest(request))
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw AIError.http(status: http.statusCode, body: String(decoding: data, as: UTF8.self))
        }
        let format = request.outputFormat ?? "mp3"
        return SpeechModelResponse(
            audio: data,
            mediaType: format == "wav" ? "audio/wav" : "audio/mpeg"
        )
    }

    func buildURLRequest(_ request: SpeechModelRequest) throws -> URLRequest {
        var body: [String: JSONValue] = [
            "model": .string(modelID),
            "text": .string(request.text),
            "voice": .string(request.voice ?? "ava")
        ]
        if let speed = request.speed { body["speed"] = .number(speed) }
        if let outputFormat = request.outputFormat { body["format"] = .string(outputFormat) }
        if case .object(let options)? = request.providerOptions {
            for (key, value) in options { body[key] = value }
        }

        var urlRequest = URLRequest(url: baseURL.appendingPathComponent("v1/ai/speech/bytes"))
        urlRequest.httpMethod = "POST"
        urlRequest.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        urlRequest.setValue("application/json", forHTTPHeaderField: "content-type")
        for (field, value) in headers { urlRequest.setValue(value, forHTTPHeaderField: field) }
        urlRequest.httpBody = try JSONEncoder().encode(JSONValue.object(body))
        return urlRequest
    }
}

public struct SarvamSpeechModel: SpeechModel {
    public let provider = "sarvam"
    public let modelID: String

    private let apiKey: String
    private let baseURL: URL
    private let targetLanguage: String
    private let headers: [String: String]
    private let urlSession: URLSession

    public init(
        _ modelID: String = "bulbul:v3",
        apiKey: String? = nil,
        targetLanguage: String = "en-IN",
        baseURL: URL = URL(string: "https://api.sarvam.ai")!,
        headers: [String: String] = [:],
        urlSession: URLSession = .shared
    ) {
        self.modelID = modelID
        self.apiKey = apiKey ?? ProcessInfo.processInfo.environment["SARVAM_API_KEY"] ?? ""
        self.targetLanguage = targetLanguage
        self.baseURL = baseURL
        self.headers = headers
        self.urlSession = urlSession
    }

    public func generateSpeech(_ request: SpeechModelRequest) async throws -> SpeechModelResponse {
        let (data, response) = try await urlSession.data(for: try buildURLRequest(request))
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw AIError.http(status: http.statusCode, body: String(decoding: data, as: UTF8.self))
        }
        let decoded = try JSONDecoder().decode(JSONValue.self, from: data)
        guard let base64 = decoded["audios"]?.arrayValue?.first?.stringValue,
              let audio = Data(base64Encoded: base64)
        else { throw AIError.decoding("Sarvam text-to-speech returned no audio") }
        return SpeechModelResponse(
            audio: audio, mediaType: Self.mediaType(for: request.outputFormat)
        )
    }

    static func mediaType(for codec: String?) -> String {
        switch codec {
        case "mp3": "audio/mpeg"
        case "opus": "audio/opus"
        case "flac": "audio/flac"
        case "aac": "audio/aac"
        case "mulaw": "audio/basic"
        case "alaw": "audio/x-alaw-basic"
        default: "audio/wav"
        }
    }

    func buildURLRequest(_ request: SpeechModelRequest) throws -> URLRequest {
        var body: [String: JSONValue] = [
            "model": .string(modelID),
            "text": .string(request.text),
            "target_language_code": .string(targetLanguage)
        ]
        if let voice = request.voice { body["speaker"] = .string(voice) }
        if let speed = request.speed { body["pace"] = .number(speed) }
        if let outputFormat = request.outputFormat {
            body["output_audio_codec"] = .string(outputFormat)
        }
        if case .object(let options)? = request.providerOptions {
            for (key, value) in options { body[key] = value }
        }

        var urlRequest = URLRequest(url: baseURL.appendingPathComponent("text-to-speech"))
        urlRequest.httpMethod = "POST"
        urlRequest.setValue(apiKey, forHTTPHeaderField: "api-subscription-key")
        urlRequest.setValue("application/json", forHTTPHeaderField: "content-type")
        for (field, value) in headers { urlRequest.setValue(value, forHTTPHeaderField: field) }
        urlRequest.httpBody = try JSONEncoder().encode(JSONValue.object(body))
        return urlRequest
    }
}

public struct HumeSpeechModel: SpeechModel {
    public let provider = "hume"
    public let modelID: String

    private let apiKey: String
    private let baseURL: URL
    private let headers: [String: String]
    private let urlSession: URLSession

    public init(
        _ modelID: String = "default",
        apiKey: String? = nil,
        baseURL: URL = URL(string: "https://api.hume.ai")!,
        headers: [String: String] = [:],
        urlSession: URLSession = .shared
    ) {
        self.modelID = modelID
        self.apiKey = apiKey ?? ProcessInfo.processInfo.environment["HUME_API_KEY"] ?? ""
        self.baseURL = baseURL
        self.headers = headers
        self.urlSession = urlSession
    }

    public func generateSpeech(_ request: SpeechModelRequest) async throws -> SpeechModelResponse {
        let (data, response) = try await urlSession.data(for: try buildURLRequest(request))
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw AIError.http(status: http.statusCode, body: String(decoding: data, as: UTF8.self))
        }
        let format = request.outputFormat ?? "mp3"
        return SpeechModelResponse(
            audio: data,
            mediaType: format == "wav" ? "audio/wav" : (format == "pcm" ? "audio/pcm" : "audio/mpeg")
        )
    }

    func buildURLRequest(_ request: SpeechModelRequest) throws -> URLRequest {
        var utterance: [String: JSONValue] = ["text": .string(request.text)]
        if let voice = request.voice {
            utterance["voice"] = .object(["id": .string(voice)])
        }
        if let instructions = request.instructions {
            utterance["description"] = .string(instructions)
        }
        if let speed = request.speed { utterance["speed"] = .number(speed) }

        var body: [String: JSONValue] = ["utterances": .array([.object(utterance)])]
        if let outputFormat = request.outputFormat {
            body["format"] = .object(["type": .string(outputFormat)])
        }
        if case .object(let options)? = request.providerOptions {
            for (key, value) in options { body[key] = value }
        }

        var urlRequest = URLRequest(url: baseURL.appendingPathComponent("v0/tts/file"))
        urlRequest.httpMethod = "POST"
        urlRequest.setValue(apiKey, forHTTPHeaderField: "X-Hume-Api-Key")
        urlRequest.setValue("application/json", forHTTPHeaderField: "content-type")
        for (field, value) in headers { urlRequest.setValue(value, forHTTPHeaderField: field) }
        urlRequest.httpBody = try JSONEncoder().encode(JSONValue.object(body))
        return urlRequest
    }
}

public struct DeepgramSpeechModel: SpeechModel {
    public let provider = "deepgram"
    public let modelID: String

    private let apiKey: String
    private let baseURL: URL
    private let headers: [String: String]
    private let urlSession: URLSession

    public init(
        _ modelID: String = "aura-2-thalia-en",
        apiKey: String? = nil,
        baseURL: URL = URL(string: "https://api.deepgram.com")!,
        headers: [String: String] = [:],
        urlSession: URLSession = .shared
    ) {
        self.modelID = modelID
        self.apiKey = apiKey ?? ProcessInfo.processInfo.environment["DEEPGRAM_API_KEY"] ?? ""
        self.baseURL = baseURL
        self.headers = headers
        self.urlSession = urlSession
    }

    public func generateSpeech(_ request: SpeechModelRequest) async throws -> SpeechModelResponse {
        let (data, response) = try await urlSession.data(for: try buildURLRequest(request))
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw AIError.http(status: http.statusCode, body: String(decoding: data, as: UTF8.self))
        }
        return SpeechModelResponse(audio: data, mediaType: "audio/mpeg")
    }

    func buildURLRequest(_ request: SpeechModelRequest) throws -> URLRequest {
        var components = URLComponents(
            url: baseURL.appendingPathComponent("v1/speak"), resolvingAgainstBaseURL: false
        )!
        components.queryItems = [URLQueryItem(name: "model", value: modelID)]

        var urlRequest = URLRequest(url: components.url!)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("Token \(apiKey)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue("application/json", forHTTPHeaderField: "content-type")
        for (field, value) in headers { urlRequest.setValue(value, forHTTPHeaderField: field) }
        urlRequest.httpBody = try JSONEncoder().encode(
            JSONValue.object(["text": .string(request.text)])
        )
        return urlRequest
    }
}
