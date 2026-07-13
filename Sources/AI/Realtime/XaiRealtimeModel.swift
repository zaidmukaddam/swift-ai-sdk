import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct XaiRealtimeModel: RealtimeModel {
    public let provider = "xai"
    public let modelID: String

    private let apiKey: String
    private let baseURL: URL
    private let headers: [String: String]
    private let urlSession: URLSession

    public init(
        _ modelID: String = "grok-voice-latest",
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

    public func createClientSecret(
        options: RealtimeClientSecretOptions
    ) async throws -> RealtimeClientSecret {
        var body: [String: JSONValue] = [:]
        if let seconds = options.expiresAfterSeconds {
            body["expires_after"] = .object(["seconds": .number(Double(seconds))])
        }

        var request = URLRequest(url: baseURL.appendingPathComponent("realtime/client_secrets"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        for (field, value) in headers { request.setValue(value, forHTTPHeaderField: field) }
        request.httpBody = try JSONEncoder().encode(JSONValue.object(body))

        let (data, response) = try await urlSession.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw AIError.http(status: http.statusCode, body: String(decoding: data, as: UTF8.self))
        }
        let decoded = try JSONDecoder().decode(JSONValue.self, from: data)
        guard let token = decoded["value"]?.stringValue else {
            throw AIError.decoding("xAI realtime client secret response had no value")
        }
        return RealtimeClientSecret(
            token: token,
            url: OpenAIRealtimeModel.webSocketURL(baseURL: baseURL, modelID: modelID),
            expiresAt: decoded["expires_at"]?.intValue
        )
    }

    public func webSocketConfig(token: String, url: String) -> RealtimeWebSocketConfig {
        RealtimeWebSocketConfig(
            url: URL(string: url) ?? baseURL,
            protocols: ["xai-client-secret.\(token)"]
        )
    }

    public func parseServerEvent(_ raw: JSONValue) -> [RealtimeServerEvent] {
        [OpenAIRealtimeModel.parseEvent(
            raw,
            textDeltaType: "response.text.delta",
            textDoneType: "response.text.done"
        )]
    }

    public func serializeClientEvent(_ event: RealtimeClientEvent) -> JSONValue? {
        switch event {
        case .sessionUpdate(let config):
            return .object(["type": "session.update", "session": buildSessionConfig(config)])
        case .inputAudioAppend(let audio):
            return .object(["type": "input_audio_buffer.append", "audio": .string(audio)])
        case .inputAudioCommit:
            return .object(["type": "input_audio_buffer.commit"])
        case .inputAudioClear:
            return .object(["type": "input_audio_buffer.clear"])
        case .conversationItemCreate(let item):
            return OpenAIRealtimeModel.serializeConversationItem(item)
        case .conversationItemTruncate:
            return nil
        case .responseCreate(let modalities, let instructions):
            var response: [String: JSONValue] = [:]
            if let modalities {
                response["modalities"] = .array(modalities.map { .string($0) })
            }
            if let instructions { response["instructions"] = .string(instructions) }
            var payload: [String: JSONValue] = ["type": "response.create"]
            if !response.isEmpty { payload["response"] = .object(response) }
            return .object(payload)
        case .responseCancel:
            return .object(["type": "response.cancel"])
        }
    }

    public func buildSessionConfig(_ config: RealtimeSessionConfig) -> JSONValue {
        var session: [String: JSONValue] = [:]
        if let instructions = config.instructions {
            session["instructions"] = .string(instructions)
        }
        if let voice = config.voice { session["voice"] = .string(voice) }

        var audio: [String: JSONValue] = [:]
        if let format = config.inputAudioFormat {
            var wire: [String: JSONValue] = ["type": .string(format.type)]
            if let rate = format.rate { wire["rate"] = .number(Double(rate)) }
            audio["input"] = .object(["format": .object(wire)])
        }
        if let format = config.outputAudioFormat {
            var wire: [String: JSONValue] = ["type": .string(format.type)]
            if let rate = format.rate { wire["rate"] = .number(Double(rate)) }
            audio["output"] = .object(["format": .object(wire)])
        }
        if !audio.isEmpty { session["audio"] = .object(audio) }

        if let vad = config.turnDetection {
            if vad.type == .disabled {
                session["turn_detection"] = .null
            } else {
                var wire: [String: JSONValue] = ["type": "server_vad"]
                if let threshold = vad.threshold { wire["threshold"] = .number(threshold) }
                if let silence = vad.silenceDurationMs {
                    wire["silence_duration_ms"] = .number(Double(silence))
                }
                if let padding = vad.prefixPaddingMs {
                    wire["prefix_padding_ms"] = .number(Double(padding))
                }
                session["turn_detection"] = .object(wire)
            }
        }

        if let tools = config.tools, !tools.isEmpty {
            session["tools"] = .array(tools.map { tool in
                var wire: [String: JSONValue] = [
                    "type": "function",
                    "name": .string(tool.name),
                    "parameters": tool.parameters
                ]
                if let description = tool.description {
                    wire["description"] = .string(description)
                }
                return .object(wire)
            })
        }

        if case .object(let options)? = config.providerOptions {
            for (key, value) in options {
                if key == "tools", case .array(let extra) = value {
                    let existing = session["tools"]?.arrayValue ?? []
                    session["tools"] = .array(existing + extra)
                } else {
                    session[key] = value
                }
            }
        }
        return .object(session)
    }
}
