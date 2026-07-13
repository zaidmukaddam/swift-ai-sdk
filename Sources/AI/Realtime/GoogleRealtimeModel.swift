import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct GoogleRealtimeModel: RealtimeModel {
    public let provider = "google"
    public let modelID: String

    private let apiKey: String
    private let baseURL: URL
    private let headers: [String: String]
    private let urlSession: URLSession
    private let mapper = Mapper()

    public init(
        _ modelID: String,
        apiKey: String? = nil,
        baseURL: URL = URL(string: "https://generativelanguage.googleapis.com/v1beta")!,
        headers: [String: String] = [:],
        urlSession: URLSession = .shared
    ) {
        self.modelID = modelID
        self.apiKey = apiKey
            ?? ProcessInfo.processInfo.environment["GOOGLE_GENERATIVE_AI_API_KEY"] ?? ""
        self.baseURL = baseURL
        self.headers = headers
        self.urlSession = urlSession
    }

    static func realtimeRoot(_ baseURL: URL) -> String {
        var path = baseURL.path
        for version in ["/v1beta", "/v1alpha"] where path.hasSuffix(version) {
            path = String(path.dropLast(version.count))
        }
        let host = baseURL.host ?? "generativelanguage.googleapis.com"
        return "\(host)\(path)"
    }

    static func authTokensURL(_ baseURL: URL) -> String {
        "https://\(realtimeRoot(baseURL))/v1alpha/auth_tokens"
    }

    static func webSocketURL(_ baseURL: URL) -> String {
        "wss://\(realtimeRoot(baseURL))/ws/google.ai.generativelanguage.v1alpha.GenerativeService.BidiGenerateContentConstrained"
    }

    public func createClientSecret(
        options: RealtimeClientSecretOptions
    ) async throws -> RealtimeClientSecret {
        guard !apiKey.isEmpty else {
            throw AIError.invalidRequest(
                "A Google API key is required for realtime token creation"
            )
        }
        let now = Date()
        let openWindow = TimeInterval(options.expiresAfterSeconds ?? 60)
        let formatter = ISO8601DateFormatter()
        let newSessionExpireTime = formatter.string(from: now.addingTimeInterval(openWindow))
        let expireTime = formatter.string(
            from: now.addingTimeInterval(openWindow + 30 * 60)
        )

        let body: JSONValue = .object([
            "uses": .number(0),
            "expireTime": .string(expireTime),
            "newSessionExpireTime": .string(newSessionExpireTime),
            "bidiGenerateContentSetup": buildSessionConfig(
                options.sessionConfig ?? RealtimeSessionConfig()
            )
        ])

        let encodedKey = apiKey.addingPercentEncoding(
            withAllowedCharacters: .urlQueryAllowed
        ) ?? apiKey
        guard let url = URL(string: "\(Self.authTokensURL(baseURL))?key=\(encodedKey)") else {
            throw AIError.invalidRequest("Could not build the Google auth token URL")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        for (field, value) in headers { request.setValue(value, forHTTPHeaderField: field) }
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await urlSession.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw AIError.http(status: http.statusCode, body: String(decoding: data, as: UTF8.self))
        }
        let decoded = try JSONDecoder().decode(JSONValue.self, from: data)
        guard let token = decoded["name"]?.stringValue else {
            throw AIError.decoding("Google realtime auth token response had no name")
        }
        let expiresAt = decoded["expireTime"]?.stringValue
            .flatMap { ISO8601DateFormatter().date(from: $0) }
            .map { Int($0.timeIntervalSince1970) }
        return RealtimeClientSecret(
            token: token, url: Self.webSocketURL(baseURL), expiresAt: expiresAt
        )
    }

    public func webSocketConfig(token: String, url: String) -> RealtimeWebSocketConfig {
        let encoded = token.addingPercentEncoding(
            withAllowedCharacters: .urlQueryAllowed
        ) ?? token
        return RealtimeWebSocketConfig(
            url: URL(string: "\(url)?access_token=\(encoded)") ?? baseURL,
            protocols: []
        )
    }

    final class Mapper: @unchecked Sendable {
        private let lock = NSLock()
        private var turnCounter = 0
        private var hasAudio = false
        private var hasText = false
        private var hasTranscript = false
        private var turnClosed = false
        var inputAudioRate = 16000

        func withLock<R>(_ body: (Mapper) -> R) -> R {
            lock.lock()
            defer { lock.unlock() }
            return body(self)
        }

        var responseID: String { "google-resp-\(turnCounter)" }
        var itemID: String { "google-item-\(turnCounter)" }
        var inputItemID: String { "google-input-\(turnCounter)" }

        func beginTurnIfClosed() {
            guard turnClosed else { return }
            turnCounter += 1
            hasAudio = false
            hasText = false
            hasTranscript = false
            turnClosed = false
        }

        func closeTurn() -> (audio: Bool, text: Bool, transcript: Bool) {
            let flags = (hasAudio, hasText, hasTranscript)
            turnClosed = true
            return flags
        }

        func noteAudio() { hasAudio = true }
        func noteText() { hasText = true }
        func noteTranscript() { hasTranscript = true }
    }

    public func parseServerEvent(_ raw: JSONValue) -> [RealtimeServerEvent] {
        mapper.withLock { state in
            if raw["setupComplete"] != nil {
                return [.sessionCreated(sessionID: nil, raw: raw)]
            }

            if let toolCall = raw["toolCall"] {
                state.beginTurnIfClosed()
                let calls = toolCall["functionCalls"]?.arrayValue ?? []
                return calls.flatMap { call -> [RealtimeServerEvent] in
                    let callID = call["id"]?.stringValue ?? ""
                    let name = call["name"]?.stringValue ?? ""
                    let arguments = call["args"].map { value -> String in
                        let data = (try? JSONEncoder().encode(value)) ?? Data("{}".utf8)
                        return String(decoding: data, as: UTF8.self)
                    } ?? "{}"
                    return [
                        .functionCallArgumentsDelta(
                            responseID: state.responseID, itemID: state.itemID,
                            callID: callID, delta: arguments, raw: raw
                        ),
                        .functionCallArgumentsDone(
                            responseID: state.responseID, itemID: state.itemID,
                            callID: callID, name: name, arguments: arguments, raw: raw
                        )
                    ]
                }
            }

            if raw["toolCallCancellation"] != nil {
                return [.custom(rawType: "toolCallCancellation", raw: raw)]
            }

            if let serverContent = raw["serverContent"] {
                return Self.parseServerContent(serverContent, raw: raw, state: state)
            }

            if let transcript = raw["inputTranscription"]?["text"]?.stringValue {
                return [.inputTranscriptionCompleted(
                    itemID: state.inputItemID, transcript: transcript, raw: raw
                )]
            }

            let firstKey = raw.objectValue?.keys.sorted().first ?? "unknown"
            return [.custom(rawType: firstKey, raw: raw)]
        }
    }

    private static func parseServerContent(
        _ serverContent: JSONValue, raw: JSONValue, state: Mapper
    ) -> [RealtimeServerEvent] {
        var events: [RealtimeServerEvent] = []

        if serverContent["interrupted"]?.boolValue == true {
            events.append(.speechStarted(itemID: nil, raw: raw))
        }

        if let parts = serverContent["modelTurn"]?["parts"]?.arrayValue {
            state.beginTurnIfClosed()
            for part in parts {
                if let audio = part["inlineData"]?["data"]?.stringValue, !audio.isEmpty {
                    state.noteAudio()
                    events.append(.audioDelta(
                        responseID: state.responseID, itemID: state.itemID,
                        delta: audio, raw: raw
                    ))
                }
                if let text = part["text"]?.stringValue, !text.isEmpty {
                    state.noteText()
                    events.append(.textDelta(
                        responseID: state.responseID, itemID: state.itemID,
                        delta: text, raw: raw
                    ))
                }
            }
        }

        if let transcript = serverContent["outputTranscription"]?["text"]?.stringValue,
           !transcript.isEmpty {
            state.noteTranscript()
            events.append(.audioTranscriptDelta(
                responseID: state.responseID, itemID: state.itemID,
                delta: transcript, raw: raw
            ))
        }

        if let transcript = serverContent["inputTranscription"]?["text"]?.stringValue,
           !transcript.isEmpty {
            events.append(.inputTranscriptionCompleted(
                itemID: state.inputItemID, transcript: transcript, raw: raw
            ))
        }

        if serverContent["turnComplete"]?.boolValue == true {
            let flags = state.closeTurn()
            if flags.audio {
                events.append(.audioDone(
                    responseID: state.responseID, itemID: state.itemID, raw: raw
                ))
            }
            if flags.text {
                events.append(.textDone(
                    responseID: state.responseID, itemID: state.itemID, text: nil, raw: raw
                ))
            }
            if flags.transcript {
                events.append(.audioTranscriptDone(
                    responseID: state.responseID, itemID: state.itemID,
                    transcript: nil, raw: raw
                ))
            }
            events.append(.responseDone(
                responseID: state.responseID, status: "completed", raw: raw
            ))
        }

        if events.isEmpty {
            return [.custom(rawType: "serverContent", raw: raw)]
        }
        return events
    }

    public func serializeClientEvent(_ event: RealtimeClientEvent) -> JSONValue? {
        switch event {
        case .sessionUpdate(let config):
            if let rate = config.inputAudioFormat?.rate {
                mapper.withLock { $0.inputAudioRate = rate }
            }
            return .object(["setup": buildSessionConfig(config)])

        case .inputAudioAppend(let audio):
            let rate = mapper.withLock { $0.inputAudioRate }
            return .object(["realtimeInput": .object([
                "audio": .object([
                    "data": .string(audio),
                    "mimeType": .string("audio/pcm;rate=\(rate)")
                ])
            ])])

        case .inputAudioCommit:
            return .object(["realtimeInput": .object(["audioStreamEnd": .bool(true)])])

        case .inputAudioClear, .responseCreate, .responseCancel, .conversationItemTruncate:
            return nil

        case .conversationItemCreate(let item):
            switch item {
            case .textMessage(let text):
                return .object(["realtimeInput": .object(["text": .string(text)])])
            case .audioMessage:
                return nil
            case .functionCallOutput(let callID, let name, let output):
                let parsed = (try? JSONDecoder().decode(
                    JSONValue.self, from: Data(output.utf8)
                )) ?? .object([:])
                var response: [String: JSONValue] = [
                    "id": .string(callID), "response": parsed
                ]
                if let name { response["name"] = .string(name) }
                return .object(["toolResponse": .object([
                    "functionResponses": .array([.object(response)])
                ])])
            }
        }
    }

    public func buildSessionConfig(_ config: RealtimeSessionConfig) -> JSONValue {
        var setup: [String: JSONValue] = [
            "model": .string(modelID.contains("/") ? modelID : "models/\(modelID)")
        ]

        var generationConfig: [String: JSONValue] = [
            "responseModalities": .array(
                (config.outputModalities ?? ["audio"]).map { .string($0.uppercased()) }
            )
        ]
        if let voice = config.voice {
            generationConfig["speechConfig"] = .object([
                "voiceConfig": .object([
                    "prebuiltVoiceConfig": .object(["voiceName": .string(voice)])
                ])
            ])
        }

        if let instructions = config.instructions {
            setup["systemInstruction"] = .object([
                "parts": .array([.object(["text": .string(instructions)])])
            ])
        }

        if let tools = config.tools, !tools.isEmpty {
            setup["tools"] = .array([.object([
                "functionDeclarations": .array(tools.map { tool in
                    var wire: [String: JSONValue] = [
                        "name": .string(tool.name),
                        "parameters": GoogleModel.cleanSchema(tool.parameters)
                    ]
                    if let description = tool.description {
                        wire["description"] = .string(description)
                    }
                    return .object(wire)
                })
            ])])
        }

        if config.inputAudioTranscription != nil {
            setup["inputAudioTranscription"] = .object([:])
        }
        if config.outputAudioTranscription != nil {
            setup["outputAudioTranscription"] = .object([:])
        }

        if case .object(let options)? = config.providerOptions {
            for (key, value) in options where key != "google" {
                setup[key] = value
            }
            if let translation = options["google"]?["translationConfig"] {
                generationConfig["translationConfig"] = translation
            }
        }
        setup["generationConfig"] = .object(generationConfig)
        return .object(setup)
    }
}
