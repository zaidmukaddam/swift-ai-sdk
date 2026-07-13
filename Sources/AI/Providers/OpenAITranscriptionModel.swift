import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct OpenAITranscriptionModel: TranscriptionModel {
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

    public func transcribe(_ request: TranscriptionModelRequest) async throws -> TranscriptionModelResponse {
        let urlRequest = try buildURLRequest(request)
        let (data, response) = try await urlSession.data(for: urlRequest)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw AIError.http(status: http.statusCode, body: String(decoding: data, as: UTF8.self))
        }

        let decoded = try JSONDecoder().decode(TranscriptionResponseBody.self, from: data)
        let segments = decoded.segments?.map {
            TranscriptionSegment(text: $0.text, startSecond: $0.start, endSecond: $0.end)
        } ?? decoded.words?.map {
            TranscriptionSegment(text: $0.word, startSecond: $0.start, endSecond: $0.end)
        } ?? []
        return TranscriptionModelResponse(
            text: decoded.text,
            segments: segments,
            language: decoded.language.flatMap { Self.iso639_1Codes[$0] },
            durationInSeconds: decoded.duration
        )
    }

    func buildURLRequest(_ request: TranscriptionModelRequest) throws -> URLRequest {
        let boundary = "swift-ai-sdk-\(UUID().uuidString)"
        var body = Data()

        func appendField(_ name: String, _ value: String) {
            body.append(Data("--\(boundary)\r\n".utf8))
            body.append(Data("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".utf8))
            body.append(Data("\(value)\r\n".utf8))
        }

        appendField("model", modelID)

        let fileExtension = Self.fileExtension(forMediaType: request.mediaType)
        body.append(Data("--\(boundary)\r\n".utf8))
        body.append(Data(
            "Content-Disposition: form-data; name=\"file\"; filename=\"audio.\(fileExtension)\"\r\n".utf8
        ))
        body.append(Data("Content-Type: \(request.mediaType)\r\n\r\n".utf8))
        body.append(request.audio)
        body.append(Data("\r\n".utf8))

        let options = request.providerOptions?["openai"]?.objectValue ?? [:]
        if options["response_format"] == nil {
            appendField("response_format", Self.responseFormat(forModel: modelID))
        }
        for (key, value) in options.sorted(by: { $0.key < $1.key }) {
            if case .array(let items) = value {
                for item in items {
                    appendField("\(key)[]", Self.fieldValue(item))
                }
            } else {
                appendField(key, Self.fieldValue(value))
            }
        }

        body.append(Data("--\(boundary)--\r\n".utf8))

        var urlRequest = URLRequest(url: baseURL.appendingPathComponent("audio/transcriptions"))
        urlRequest.httpMethod = "POST"
        if !apiKey.isEmpty {
            urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        urlRequest.setValue(
            "multipart/form-data; boundary=\(boundary)",
            forHTTPHeaderField: "content-type"
        )
        for (field, value) in headers {
            urlRequest.setValue(value, forHTTPHeaderField: field)
        }
        urlRequest.httpBody = body
        return urlRequest
    }

    static func responseFormat(forModel modelID: String) -> String {
        let jsonOnlyModels = ["gpt-4o-transcribe", "gpt-4o-mini-transcribe"]
        return jsonOnlyModels.contains(modelID) ? "json" : "verbose_json"
    }

    static func fileExtension(forMediaType mediaType: String) -> String {
        let subtype = mediaType.lowercased().split(separator: "/").dropFirst().first.map(String.init) ?? ""
        let special = ["mpeg": "mp3", "x-wav": "wav", "opus": "ogg", "mp4": "m4a", "x-m4a": "m4a"]
        return special[subtype] ?? subtype
    }

    static func fieldValue(_ value: JSONValue) -> String {
        switch value {
        case .string(let s): return s
        case .bool(let b): return b ? "true" : "false"
        case .number(let n):
            return n == n.rounded() && abs(n) < 1e15 ? String(Int(n)) : String(n)
        case .null: return "null"
        case .array, .object:
            let data = (try? JSONEncoder().encode(value)) ?? Data()
            return String(decoding: data, as: UTF8.self)
        }
    }

    static let iso639_1Codes: [String: String] = [
        "afrikaans": "af", "arabic": "ar", "armenian": "hy", "azerbaijani": "az",
        "belarusian": "be", "bosnian": "bs", "bulgarian": "bg", "catalan": "ca",
        "chinese": "zh", "croatian": "hr", "czech": "cs", "danish": "da",
        "dutch": "nl", "english": "en", "estonian": "et", "finnish": "fi",
        "french": "fr", "galician": "gl", "german": "de", "greek": "el",
        "hebrew": "he", "hindi": "hi", "hungarian": "hu", "icelandic": "is",
        "indonesian": "id", "italian": "it", "japanese": "ja", "kannada": "kn",
        "kazakh": "kk", "korean": "ko", "latvian": "lv", "lithuanian": "lt",
        "macedonian": "mk", "malay": "ms", "marathi": "mr", "maori": "mi",
        "nepali": "ne", "norwegian": "no", "persian": "fa", "polish": "pl",
        "portuguese": "pt", "romanian": "ro", "russian": "ru", "serbian": "sr",
        "slovak": "sk", "slovenian": "sl", "spanish": "es", "swahili": "sw",
        "swedish": "sv", "tagalog": "tl", "tamil": "ta", "thai": "th",
        "turkish": "tr", "ukrainian": "uk", "urdu": "ur", "vietnamese": "vi",
        "welsh": "cy"
    ]
}

private struct TranscriptionResponseBody: Decodable {
    var text: String
    var language: String?
    var duration: Double?
    var words: [Word]?
    var segments: [Segment]?

    struct Word: Decodable {
        var word: String
        var start: Double
        var end: Double
    }
    struct Segment: Decodable {
        var text: String
        var start: Double
        var end: Double
    }
}
