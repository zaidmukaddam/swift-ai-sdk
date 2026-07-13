import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct OpenAIRealtimeModel: RealtimeModel {
    public let provider = "openai"
    public let modelID: String

    private let apiKey: String
    private let baseURL: URL
    private let headers: [String: String]
    private let urlSession: URLSession

    public init(
        _ modelID: String = "gpt-realtime",
        apiKey: String? = nil,
        baseURL: URL = URL(string: "https://api.openai.com/v1")!,
        headers: [String: String] = [:],
        urlSession: URLSession = .shared
    ) {
        self.modelID = modelID
        self.apiKey = apiKey ?? ProcessInfo.processInfo.environment["OPENAI_API_KEY"] ?? ""
        self.baseURL = baseURL
        self.headers = headers
        self.urlSession = urlSession
    }

    public func createClientSecret(
        options: RealtimeClientSecretOptions
    ) async throws -> RealtimeClientSecret {
        var body: [String: JSONValue] = [
            "session": options.sessionConfig.map(buildSessionConfig)
                ?? .object(["type": "realtime", "model": .string(modelID)])
        ]
        if let seconds = options.expiresAfterSeconds {
            body["expires_after"] = .object([
                "anchor": "created_at", "seconds": .number(Double(seconds))
            ])
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
            throw AIError.decoding("OpenAI realtime client secret response had no value")
        }
        return RealtimeClientSecret(
            token: token,
            url: Self.webSocketURL(baseURL: baseURL, modelID: modelID),
            expiresAt: decoded["expires_at"]?.intValue
        )
    }

    static func webSocketURL(baseURL: URL, modelID: String) -> String {
        let host = baseURL.host ?? "api.openai.com"
        let encoded = modelID.addingPercentEncoding(
            withAllowedCharacters: .urlQueryAllowed
        ) ?? modelID
        return "wss://\(host)/v1/realtime?model=\(encoded)"
    }

    public func webSocketConfig(token: String, url: String) -> RealtimeWebSocketConfig {
        RealtimeWebSocketConfig(
            url: URL(string: url) ?? baseURL,
            protocols: ["realtime", "openai-insecure-api-key.\(token)"]
        )
    }

    public func parseServerEvent(_ raw: JSONValue) -> [RealtimeServerEvent] {
        [Self.parseEvent(raw)]
    }

    static func parseEvent(
        _ raw: JSONValue,
        textDeltaType: String = "response.output_text.delta",
        textDoneType: String = "response.output_text.done"
    ) -> RealtimeServerEvent {
        let type = raw["type"]?.stringValue ?? ""
        let itemID = raw["item_id"]?.stringValue ?? ""
        let responseID = raw["response_id"]?.stringValue ?? ""
        let delta = raw["delta"]?.stringValue ?? ""

        switch type {
        case "session.created":
            return .sessionCreated(sessionID: raw["session"]?["id"]?.stringValue, raw: raw)
        case "session.updated":
            return .sessionUpdated(raw: raw)
        case "input_audio_buffer.speech_started":
            return .speechStarted(itemID: raw["item_id"]?.stringValue, raw: raw)
        case "input_audio_buffer.speech_stopped":
            return .speechStopped(itemID: raw["item_id"]?.stringValue, raw: raw)
        case "input_audio_buffer.committed":
            return .audioCommitted(
                itemID: raw["item_id"]?.stringValue,
                previousItemID: raw["previous_item_id"]?.stringValue,
                raw: raw
            )
        case "conversation.item.added":
            return .conversationItemAdded(
                itemID: raw["item"]?["id"]?.stringValue ?? itemID, raw: raw
            )
        case "conversation.item.input_audio_transcription.completed":
            return .inputTranscriptionCompleted(
                itemID: itemID, transcript: raw["transcript"]?.stringValue ?? "", raw: raw
            )
        case "response.created":
            return .responseCreated(
                responseID: raw["response"]?["id"]?.stringValue ?? responseID, raw: raw
            )
        case "response.done":
            return .responseDone(
                responseID: raw["response"]?["id"]?.stringValue ?? responseID,
                status: raw["response"]?["status"]?.stringValue ?? "completed",
                raw: raw
            )
        case "response.output_item.added":
            return .outputItemAdded(
                responseID: responseID,
                itemID: raw["item"]?["id"]?.stringValue ?? itemID, raw: raw
            )
        case "response.output_item.done":
            return .outputItemDone(
                responseID: responseID,
                itemID: raw["item"]?["id"]?.stringValue ?? itemID, raw: raw
            )
        case "response.content_part.added":
            return .contentPartAdded(responseID: responseID, itemID: itemID, raw: raw)
        case "response.content_part.done":
            return .contentPartDone(responseID: responseID, itemID: itemID, raw: raw)
        case "response.output_audio.delta":
            return .audioDelta(responseID: responseID, itemID: itemID, delta: delta, raw: raw)
        case "response.output_audio.done":
            return .audioDone(responseID: responseID, itemID: itemID, raw: raw)
        case "response.output_audio_transcript.delta":
            return .audioTranscriptDelta(
                responseID: responseID, itemID: itemID, delta: delta, raw: raw
            )
        case "response.output_audio_transcript.done":
            return .audioTranscriptDone(
                responseID: responseID, itemID: itemID,
                transcript: raw["transcript"]?.stringValue, raw: raw
            )
        case textDeltaType:
            return .textDelta(responseID: responseID, itemID: itemID, delta: delta, raw: raw)
        case textDoneType:
            return .textDone(
                responseID: responseID, itemID: itemID,
                text: raw["text"]?.stringValue, raw: raw
            )
        case "response.function_call_arguments.delta":
            return .functionCallArgumentsDelta(
                responseID: responseID, itemID: itemID,
                callID: raw["call_id"]?.stringValue ?? "", delta: delta, raw: raw
            )
        case "response.function_call_arguments.done":
            return .functionCallArgumentsDone(
                responseID: responseID, itemID: itemID,
                callID: raw["call_id"]?.stringValue ?? "",
                name: raw["name"]?.stringValue ?? "",
                arguments: raw["arguments"]?.stringValue ?? "", raw: raw
            )
        case "error":
            return .error(
                message: raw["error"]?["message"]?.stringValue
                    ?? raw["message"]?.stringValue ?? "Unknown error",
                code: raw["error"]?["code"]?.stringValue ?? raw["code"]?.stringValue,
                raw: raw
            )
        default:
            return .custom(rawType: type, raw: raw)
        }
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
            return Self.serializeConversationItem(item)
        case .conversationItemTruncate(let itemID, let contentIndex, let audioEndMs):
            return .object([
                "type": "conversation.item.truncate",
                "item_id": .string(itemID),
                "content_index": .number(Double(contentIndex)),
                "audio_end_ms": .number(Double(audioEndMs))
            ])
        case .responseCreate(let modalities, let instructions):
            var response: [String: JSONValue] = [:]
            if let modalities {
                response["output_modalities"] = .array(modalities.map { .string($0) })
            }
            if let instructions { response["instructions"] = .string(instructions) }
            var payload: [String: JSONValue] = ["type": "response.create"]
            if !response.isEmpty { payload["response"] = .object(response) }
            return .object(payload)
        case .responseCancel:
            return .object(["type": "response.cancel"])
        }
    }

    static func serializeConversationItem(_ item: RealtimeConversationItem) -> JSONValue {
        switch item {
        case .textMessage(let text):
            return .object([
                "type": "conversation.item.create",
                "item": .object([
                    "type": "message", "role": "user",
                    "content": .array([.object(["type": "input_text", "text": .string(text)])])
                ])
            ])
        case .audioMessage(let audio):
            return .object([
                "type": "conversation.item.create",
                "item": .object([
                    "type": "message", "role": "user",
                    "content": .array([.object(["type": "input_audio", "audio": .string(audio)])])
                ])
            ])
        case .functionCallOutput(let callID, _, let output):
            return .object([
                "type": "conversation.item.create",
                "item": .object([
                    "type": "function_call_output",
                    "call_id": .string(callID),
                    "output": .string(output)
                ])
            ])
        }
    }

    public func buildSessionConfig(_ config: RealtimeSessionConfig) -> JSONValue {
        var session: [String: JSONValue] = [
            "type": "realtime",
            "model": .string(modelID)
        ]
        if let instructions = config.instructions {
            session["instructions"] = .string(instructions)
        }
        if let modalities = config.outputModalities {
            session["output_modalities"] = .array(modalities.map { .string($0) })
        }

        var audio: [String: JSONValue] = [:]
        if config.inputAudioFormat != nil
            || config.inputAudioTranscription != nil
            || config.turnDetection != nil {
            var input: [String: JSONValue] = [:]
            if let format = config.inputAudioFormat {
                var wire: [String: JSONValue] = ["type": .string(format.type)]
                if let rate = format.rate { wire["rate"] = .number(Double(rate)) }
                input["format"] = .object(wire)
            }
            if let vad = config.turnDetection {
                if vad.type == .disabled {
                    input["turn_detection"] = .null
                } else {
                    var wire: [String: JSONValue] = [
                        "type": .string(vad.type == .serverVAD ? "server_vad" : "semantic_vad")
                    ]
                    if let threshold = vad.threshold { wire["threshold"] = .number(threshold) }
                    if let silence = vad.silenceDurationMs {
                        wire["silence_duration_ms"] = .number(Double(silence))
                    }
                    if let padding = vad.prefixPaddingMs {
                        wire["prefix_padding_ms"] = .number(Double(padding))
                    }
                    input["turn_detection"] = .object(wire)
                }
            }
            if let transcription = config.inputAudioTranscription {
                var wire: [String: JSONValue] = [
                    "model": .string(transcription.model ?? "gpt-realtime-whisper")
                ]
                if let language = transcription.language { wire["language"] = .string(language) }
                if let prompt = transcription.prompt { wire["prompt"] = .string(prompt) }
                input["transcription"] = .object(wire)
            }
            audio["input"] = .object(input)
        }
        if config.outputAudioFormat != nil || config.voice != nil {
            var output: [String: JSONValue] = [:]
            if let format = config.outputAudioFormat {
                var wire: [String: JSONValue] = ["type": .string(format.type)]
                if let rate = format.rate { wire["rate"] = .number(Double(rate)) }
                output["format"] = .object(wire)
            }
            if let voice = config.voice { output["voice"] = .string(voice) }
            audio["output"] = .object(output)
        }
        if !audio.isEmpty { session["audio"] = .object(audio) }

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
            session["tool_choice"] = "auto"
        }

        if case .object(let options)? = config.providerOptions {
            for (key, value) in options { session[key] = value }
        }
        return .object(session)
    }
}
