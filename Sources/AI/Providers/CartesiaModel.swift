import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

private let cartesiaAPIVersion = "2026-03-01"

public struct CartesiaSpeechModel: SpeechModel {
    public let provider = "cartesia"
    public let modelID: String

    private let apiKey: String
    private let baseURL: URL
    private let defaultVoice: String
    private let sampleRate: Int
    private let headers: [String: String]
    private let urlSession: URLSession

    public init(
        _ modelID: String = "sonic-2",
        apiKey: String? = nil,
        voice: String = "a0e99841-438c-4a64-b679-ae501e7d6091",
        sampleRate: Int = 44100,
        baseURL: URL = URL(string: "https://api.cartesia.ai")!,
        headers: [String: String] = [:],
        urlSession: URLSession = .shared
    ) {
        self.modelID = modelID
        self.apiKey = apiKey ?? ProcessInfo.processInfo.environment["CARTESIA_API_KEY"] ?? ""
        self.defaultVoice = voice
        self.sampleRate = sampleRate
        self.baseURL = baseURL
        self.headers = headers
        self.urlSession = urlSession
    }

    public func generateSpeech(_ request: SpeechModelRequest) async throws -> SpeechModelResponse {
        let (data, response) = try await urlSession.data(for: try buildURLRequest(request))
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw AIError.http(status: http.statusCode, body: String(decoding: data, as: UTF8.self))
        }
        return SpeechModelResponse(
            audio: data, mediaType: Self.mediaType(for: request.outputFormat)
        )
    }

    static func mediaType(for container: String?) -> String {
        switch container {
        case "wav": "audio/wav"
        case "raw", "pcm": "audio/pcm"
        default: "audio/mpeg"
        }
    }

    static func outputFormat(for container: String?, sampleRate: Int) -> JSONValue {
        switch container {
        case "wav":
            return .object([
                "container": "wav",
                "encoding": "pcm_s16le",
                "sample_rate": .number(Double(sampleRate))
            ])
        case "raw", "pcm":
            return .object([
                "container": "raw",
                "encoding": "pcm_f32le",
                "sample_rate": .number(Double(sampleRate))
            ])
        default:
            return .object([
                "container": "mp3",
                "sample_rate": .number(Double(sampleRate)),
                "bit_rate": .number(128000)
            ])
        }
    }

    func buildURLRequest(_ request: SpeechModelRequest) throws -> URLRequest {
        var body: [String: JSONValue] = [
            "model_id": .string(modelID),
            "transcript": .string(request.text),
            "voice": .object(["mode": "id", "id": .string(request.voice ?? defaultVoice)]),
            "output_format": Self.outputFormat(for: request.outputFormat, sampleRate: sampleRate)
        ]
        if case .object(let options)? = request.providerOptions {
            for (key, value) in options { body[key] = value }
        }

        var urlRequest = URLRequest(url: baseURL.appendingPathComponent("tts/bytes"))
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue(cartesiaAPIVersion, forHTTPHeaderField: "Cartesia-Version")
        urlRequest.setValue("application/json", forHTTPHeaderField: "content-type")
        for (field, value) in headers { urlRequest.setValue(value, forHTTPHeaderField: field) }
        urlRequest.httpBody = try JSONEncoder().encode(JSONValue.object(body))
        return urlRequest
    }
}

public struct CartesiaTranscriptionModel: TranscriptionModel {
    public let provider = "cartesia"
    public let modelID: String

    private let apiKey: String
    private let baseURL: URL
    private let headers: [String: String]
    private let urlSession: URLSession

    public init(
        _ modelID: String = "ink-whisper",
        apiKey: String? = nil,
        baseURL: URL = URL(string: "https://api.cartesia.ai")!,
        headers: [String: String] = [:],
        urlSession: URLSession = .shared
    ) {
        self.modelID = modelID
        self.apiKey = apiKey ?? ProcessInfo.processInfo.environment["CARTESIA_API_KEY"] ?? ""
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
                guard let text = word["word"]?.stringValue ?? word["text"]?.stringValue else {
                    return nil
                }
                return TranscriptionSegment(
                    text: text,
                    startSecond: word["start"]?.doubleValue ?? 0,
                    endSecond: word["end"]?.doubleValue ?? 0
                )
            },
            language: decoded["language"]?.stringValue,
            durationInSeconds: decoded["duration"]?.doubleValue
        )
    }

    func buildURLRequest(_ request: TranscriptionModelRequest) -> URLRequest {
        var form = MultipartForm(boundary: "swift-ai-sdk-cartesia-stt")
        form.addField(name: "model", value: modelID)
        if case .object(let options)? = request.providerOptions {
            for (key, value) in options where key != "model" {
                if case .string(let string) = value {
                    form.addField(name: key, value: string)
                }
            }
        }
        form.addFile(
            name: "file",
            filename: "audio.\(SarvamTranscriptionModel.fileExtension(for: request.mediaType))",
            mediaType: request.mediaType,
            data: request.audio
        )

        var urlRequest = URLRequest(url: baseURL.appendingPathComponent("stt"))
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue(cartesiaAPIVersion, forHTTPHeaderField: "Cartesia-Version")
        urlRequest.setValue(
            "multipart/form-data; boundary=\(form.boundary)", forHTTPHeaderField: "content-type"
        )
        for (field, value) in headers { urlRequest.setValue(value, forHTTPHeaderField: field) }
        urlRequest.httpBody = form.finish()
        return urlRequest
    }
}
