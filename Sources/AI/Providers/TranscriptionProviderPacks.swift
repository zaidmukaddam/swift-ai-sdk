import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct DeepgramTranscriptionModel: TranscriptionModel {
    public let provider = "deepgram"
    public let modelID: String

    private let apiKey: String
    private let baseURL: URL
    private let headers: [String: String]
    private let urlSession: URLSession

    public init(
        _ modelID: String = "nova-3",
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

    public func transcribe(_ request: TranscriptionModelRequest) async throws -> TranscriptionModelResponse {
        let (data, response) = try await urlSession.data(for: buildURLRequest(request))
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw AIError.http(status: http.statusCode, body: String(decoding: data, as: UTF8.self))
        }
        let decoded = try JSONDecoder().decode(JSONValue.self, from: data)
        let alternative = decoded["results"]?["channels"]?.arrayValue?.first?["alternatives"]?
            .arrayValue?.first
        let words = alternative?["words"]?.arrayValue ?? []
        return TranscriptionModelResponse(
            text: alternative?["transcript"]?.stringValue ?? "",
            segments: words.compactMap { word in
                guard let text = word["word"]?.stringValue else { return nil }
                return TranscriptionSegment(
                    text: text,
                    startSecond: word["start"]?.doubleValue ?? 0,
                    endSecond: word["end"]?.doubleValue ?? 0
                )
            },
            language: nil,
            durationInSeconds: decoded["metadata"]?["duration"]?.doubleValue
        )
    }

    func buildURLRequest(_ request: TranscriptionModelRequest) -> URLRequest {
        var components = URLComponents(
            url: baseURL.appendingPathComponent("v1/listen"), resolvingAgainstBaseURL: false
        )!
        components.queryItems = [
            URLQueryItem(name: "model", value: modelID),
            URLQueryItem(name: "smart_format", value: "true")
        ]

        var urlRequest = URLRequest(url: components.url!)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("Token \(apiKey)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue(request.mediaType, forHTTPHeaderField: "content-type")
        for (field, value) in headers { urlRequest.setValue(value, forHTTPHeaderField: field) }
        urlRequest.httpBody = request.audio
        return urlRequest
    }
}

public struct SarvamTranscriptionModel: TranscriptionModel {
    public let provider = "sarvam"
    public let modelID: String

    private let apiKey: String
    private let baseURL: URL
    private let headers: [String: String]
    private let urlSession: URLSession

    public init(
        _ modelID: String = "saaras:v3",
        apiKey: String? = nil,
        baseURL: URL = URL(string: "https://api.sarvam.ai")!,
        headers: [String: String] = [:],
        urlSession: URLSession = .shared
    ) {
        self.modelID = modelID
        self.apiKey = apiKey ?? ProcessInfo.processInfo.environment["SARVAM_API_KEY"] ?? ""
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
        return TranscriptionModelResponse(
            text: decoded["transcript"]?.stringValue ?? "",
            language: decoded["language_code"]?.stringValue
        )
    }

    func buildURLRequest(_ request: TranscriptionModelRequest) -> URLRequest {
        var form = MultipartForm(boundary: "swift-ai-sdk-sarvam")
        form.addField(name: "model", value: modelID)
        if case .object(let options)? = request.providerOptions {
            for (key, value) in options {
                if case .string(let string) = value {
                    form.addField(name: key, value: string)
                }
            }
        }
        form.addFile(
            name: "file",
            filename: "audio.\(Self.fileExtension(for: request.mediaType))",
            mediaType: request.mediaType,
            data: request.audio
        )

        var urlRequest = URLRequest(url: baseURL.appendingPathComponent("speech-to-text"))
        urlRequest.httpMethod = "POST"
        urlRequest.setValue(apiKey, forHTTPHeaderField: "api-subscription-key")
        urlRequest.setValue(
            "multipart/form-data; boundary=\(form.boundary)", forHTTPHeaderField: "content-type"
        )
        for (field, value) in headers { urlRequest.setValue(value, forHTTPHeaderField: field) }
        urlRequest.httpBody = form.finish()
        return urlRequest
    }

    static func fileExtension(for mediaType: String) -> String {
        switch mediaType.split(separator: "/").last.map(String.init) {
        case "mpeg", "mp3": "mp3"
        case "x-wav", "wave": "wav"
        default: mediaType.split(separator: "/").last.map(String.init) ?? "wav"
        }
    }
}

public struct AssemblyAITranscriptionModel: TranscriptionModel {
    public let provider = "assemblyai"
    public let modelID: String

    private let apiKey: String
    private let baseURL: URL
    private let headers: [String: String]
    private let urlSession: URLSession
    private let pollInterval: TimeInterval
    private let pollTimeout: TimeInterval

    public init(
        _ modelID: String = "universal",
        apiKey: String? = nil,
        baseURL: URL = URL(string: "https://api.assemblyai.com")!,
        headers: [String: String] = [:],
        pollInterval: TimeInterval = 1,
        pollTimeout: TimeInterval = 300,
        urlSession: URLSession = .shared
    ) {
        self.modelID = modelID
        self.apiKey = apiKey ?? ProcessInfo.processInfo.environment["ASSEMBLYAI_API_KEY"] ?? ""
        self.baseURL = baseURL
        self.headers = headers
        self.pollInterval = pollInterval
        self.pollTimeout = pollTimeout
        self.urlSession = urlSession
    }

    public func transcribe(_ request: TranscriptionModelRequest) async throws -> TranscriptionModelResponse {
        var upload = URLRequest(url: baseURL.appendingPathComponent("v2/upload"))
        upload.httpMethod = "POST"
        upload.setValue(apiKey, forHTTPHeaderField: "authorization")
        upload.setValue("application/octet-stream", forHTTPHeaderField: "content-type")
        upload.httpBody = request.audio
        let (uploadData, uploadResponse) = try await urlSession.data(for: upload)
        if let http = uploadResponse as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw AIError.http(status: http.statusCode, body: String(decoding: uploadData, as: UTF8.self))
        }
        guard let audioURL = try JSONDecoder().decode(JSONValue.self, from: uploadData)["upload_url"]?.stringValue
        else { throw AIError.decoding("AssemblyAI upload returned no upload_url") }

        var create = URLRequest(url: baseURL.appendingPathComponent("v2/transcript"))
        create.httpMethod = "POST"
        create.setValue(apiKey, forHTTPHeaderField: "authorization")
        create.setValue("application/json", forHTTPHeaderField: "content-type")
        var body: [String: JSONValue] = [
            "audio_url": .string(audioURL),
            "speech_model": .string(modelID)
        ]
        if case .object(let options)? = request.providerOptions {
            for (key, value) in options { body[key] = value }
        }
        create.httpBody = try JSONEncoder().encode(JSONValue.object(body))
        let (createData, createResponse) = try await urlSession.data(for: create)
        if let http = createResponse as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw AIError.http(status: http.statusCode, body: String(decoding: createData, as: UTF8.self))
        }
        guard let jobID = try JSONDecoder().decode(JSONValue.self, from: createData)["id"]?.stringValue
        else { throw AIError.decoding("AssemblyAI returned no transcript id") }

        let deadline = Date().addingTimeInterval(pollTimeout)
        while true {
            try await Task.sleep(nanoseconds: UInt64(pollInterval * 1_000_000_000))
            if Date() > deadline {
                throw AIError.transport("AssemblyAI transcription timed out")
            }
            var poll = URLRequest(url: baseURL.appendingPathComponent("v2/transcript/\(jobID)"))
            poll.setValue(apiKey, forHTTPHeaderField: "authorization")
            let (pollData, _) = try await urlSession.data(for: poll)
            let status = try JSONDecoder().decode(JSONValue.self, from: pollData)
            if let terminal = try Self.resolvePoll(status) { return terminal }
        }
    }

    static func resolvePoll(_ status: JSONValue) throws -> TranscriptionModelResponse? {
        switch status["status"]?.stringValue {
        case "completed":
            let words = status["words"]?.arrayValue ?? []
            return TranscriptionModelResponse(
                text: status["text"]?.stringValue ?? "",
                segments: words.compactMap { word in
                    guard let text = word["text"]?.stringValue else { return nil }
                    return TranscriptionSegment(
                        text: text,
                        startSecond: (word["start"]?.doubleValue ?? 0) / 1000,
                        endSecond: (word["end"]?.doubleValue ?? 0) / 1000
                    )
                },
                language: status["language_code"]?.stringValue,
                durationInSeconds: status["audio_duration"]?.doubleValue
            )
        case "error":
            throw AIError.transport(
                "AssemblyAI transcription failed: \(status["error"]?.stringValue ?? "unknown")"
            )
        default:
            return nil
        }
    }
}

public struct RevAITranscriptionModel: TranscriptionModel {
    public let provider = "revai"
    public let modelID: String

    private let apiKey: String
    private let baseURL: URL
    private let headers: [String: String]
    private let urlSession: URLSession
    private let pollInterval: TimeInterval
    private let pollTimeout: TimeInterval

    public init(
        _ modelID: String = "machine",
        apiKey: String? = nil,
        baseURL: URL = URL(string: "https://api.rev.ai")!,
        headers: [String: String] = [:],
        pollInterval: TimeInterval = 2,
        pollTimeout: TimeInterval = 600,
        urlSession: URLSession = .shared
    ) {
        self.modelID = modelID
        self.apiKey = apiKey ?? ProcessInfo.processInfo.environment["REVAI_API_KEY"] ?? ""
        self.baseURL = baseURL
        self.headers = headers
        self.pollInterval = pollInterval
        self.pollTimeout = pollTimeout
        self.urlSession = urlSession
    }

    public func transcribe(_ request: TranscriptionModelRequest) async throws -> TranscriptionModelResponse {
        var form = MultipartForm(boundary: "swift-ai-sdk-revai")
        form.addField(name: "options", value: #"{"transcriber":"\#(modelID)"}"#)
        form.addFile(name: "media", filename: "audio", mediaType: request.mediaType, data: request.audio)

        var submit = URLRequest(url: baseURL.appendingPathComponent("speechtotext/v1/jobs"))
        submit.httpMethod = "POST"
        submit.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        submit.setValue(
            "multipart/form-data; boundary=\(form.boundary)", forHTTPHeaderField: "content-type"
        )
        submit.httpBody = form.finish()
        let (submitData, submitResponse) = try await urlSession.data(for: submit)
        if let http = submitResponse as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw AIError.http(status: http.statusCode, body: String(decoding: submitData, as: UTF8.self))
        }
        guard let jobID = try JSONDecoder().decode(JSONValue.self, from: submitData)["id"]?.stringValue
        else { throw AIError.decoding("Rev.ai returned no job id") }

        let deadline = Date().addingTimeInterval(pollTimeout)
        while true {
            try await Task.sleep(nanoseconds: UInt64(pollInterval * 1_000_000_000))
            if Date() > deadline { throw AIError.transport("Rev.ai transcription timed out") }
            var poll = URLRequest(url: baseURL.appendingPathComponent("speechtotext/v1/jobs/\(jobID)"))
            poll.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            let (pollData, _) = try await urlSession.data(for: poll)
            let status = try JSONDecoder().decode(JSONValue.self, from: pollData)
            switch status["status"]?.stringValue {
            case "transcribed":
                return try await fetchTranscript(jobID: jobID)
            case "failed":
                throw AIError.transport(
                    "Rev.ai transcription failed: \(status["failure_detail"]?.stringValue ?? "unknown")"
                )
            default:
                continue
            }
        }
    }

    private func fetchTranscript(jobID: String) async throws -> TranscriptionModelResponse {
        var fetch = URLRequest(
            url: baseURL.appendingPathComponent("speechtotext/v1/jobs/\(jobID)/transcript")
        )
        fetch.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        fetch.setValue("application/vnd.rev.transcript.v1.0+json", forHTTPHeaderField: "Accept")
        let (data, response) = try await urlSession.data(for: fetch)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw AIError.http(status: http.statusCode, body: String(decoding: data, as: UTF8.self))
        }
        return try Self.parseTranscript(try JSONDecoder().decode(JSONValue.self, from: data))
    }

    static func parseTranscript(_ transcript: JSONValue) throws -> TranscriptionModelResponse {
        var text = ""
        var segments: [TranscriptionSegment] = []
        for monologue in transcript["monologues"]?.arrayValue ?? [] {
            for element in monologue["elements"]?.arrayValue ?? [] {
                let value = element["value"]?.stringValue ?? ""
                text += value
                if element["type"]?.stringValue == "text" {
                    segments.append(TranscriptionSegment(
                        text: value,
                        startSecond: element["ts"]?.doubleValue ?? 0,
                        endSecond: element["end_ts"]?.doubleValue ?? 0
                    ))
                }
            }
        }
        return TranscriptionModelResponse(
            text: text, segments: segments, language: nil, durationInSeconds: nil
        )
    }
}

public struct GladiaTranscriptionModel: TranscriptionModel {
    public let provider = "gladia"
    public let modelID: String

    private let apiKey: String
    private let baseURL: URL
    private let headers: [String: String]
    private let urlSession: URLSession
    private let pollInterval: TimeInterval
    private let pollTimeout: TimeInterval

    public init(
        _ modelID: String = "default",
        apiKey: String? = nil,
        baseURL: URL = URL(string: "https://api.gladia.io")!,
        headers: [String: String] = [:],
        pollInterval: TimeInterval = 1,
        pollTimeout: TimeInterval = 300,
        urlSession: URLSession = .shared
    ) {
        self.modelID = modelID
        self.apiKey = apiKey ?? ProcessInfo.processInfo.environment["GLADIA_API_KEY"] ?? ""
        self.baseURL = baseURL
        self.headers = headers
        self.pollInterval = pollInterval
        self.pollTimeout = pollTimeout
        self.urlSession = urlSession
    }

    public func transcribe(_ request: TranscriptionModelRequest) async throws -> TranscriptionModelResponse {
        var form = MultipartForm(boundary: "swift-ai-sdk-gladia")
        form.addFile(name: "audio", filename: "audio", mediaType: request.mediaType, data: request.audio)
        var upload = URLRequest(url: baseURL.appendingPathComponent("v2/upload"))
        upload.httpMethod = "POST"
        upload.setValue(apiKey, forHTTPHeaderField: "x-gladia-key")
        upload.setValue(
            "multipart/form-data; boundary=\(form.boundary)", forHTTPHeaderField: "content-type"
        )
        upload.httpBody = form.finish()
        let (uploadData, uploadResponse) = try await urlSession.data(for: upload)
        if let http = uploadResponse as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw AIError.http(status: http.statusCode, body: String(decoding: uploadData, as: UTF8.self))
        }
        guard let audioURL = try JSONDecoder().decode(JSONValue.self, from: uploadData)["audio_url"]?.stringValue
        else { throw AIError.decoding("Gladia upload returned no audio_url") }

        var create = URLRequest(url: baseURL.appendingPathComponent("v2/pre-recorded"))
        create.httpMethod = "POST"
        create.setValue(apiKey, forHTTPHeaderField: "x-gladia-key")
        create.setValue("application/json", forHTTPHeaderField: "content-type")
        var body: [String: JSONValue] = ["audio_url": .string(audioURL)]
        if case .object(let options)? = request.providerOptions {
            for (key, value) in options { body[key] = value }
        }
        create.httpBody = try JSONEncoder().encode(JSONValue.object(body))
        let (createData, createResponse) = try await urlSession.data(for: create)
        if let http = createResponse as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw AIError.http(status: http.statusCode, body: String(decoding: createData, as: UTF8.self))
        }
        let created = try JSONDecoder().decode(JSONValue.self, from: createData)
        guard let resultURLString = created["result_url"]?.stringValue,
              let resultURL = URL(string: resultURLString)
        else { throw AIError.decoding("Gladia returned no result_url") }

        let deadline = Date().addingTimeInterval(pollTimeout)
        while true {
            try await Task.sleep(nanoseconds: UInt64(pollInterval * 1_000_000_000))
            if Date() > deadline { throw AIError.transport("Gladia transcription timed out") }
            var poll = URLRequest(url: resultURL)
            poll.setValue(apiKey, forHTTPHeaderField: "x-gladia-key")
            let (pollData, _) = try await urlSession.data(for: poll)
            let status = try JSONDecoder().decode(JSONValue.self, from: pollData)
            if let terminal = try Self.resolvePoll(status) { return terminal }
        }
    }

    static func resolvePoll(_ status: JSONValue) throws -> TranscriptionModelResponse? {
        switch status["status"]?.stringValue {
        case "done":
            let transcription = status["result"]?["transcription"]
            let utterances = transcription?["utterances"]?.arrayValue ?? []
            return TranscriptionModelResponse(
                text: transcription?["full_transcript"]?.stringValue ?? "",
                segments: utterances.compactMap { utterance in
                    guard let text = utterance["text"]?.stringValue else { return nil }
                    return TranscriptionSegment(
                        text: text,
                        startSecond: utterance["start"]?.doubleValue ?? 0,
                        endSecond: utterance["end"]?.doubleValue ?? 0
                    )
                },
                language: utterances.first?["language"]?.stringValue,
                durationInSeconds: status["result"]?["metadata"]?["audio_duration"]?.doubleValue
            )
        case "error":
            throw AIError.transport(
                "Gladia transcription failed: \(status["error_code"]?.stringValue ?? "unknown")"
            )
        default:
            return nil
        }
    }
}
