import Foundation

public struct RealtimeToolDefinition: Sendable {
    public var name: String
    public var description: String?
    public var parameters: JSONValue

    public init(name: String, description: String? = nil, parameters: JSONValue) {
        self.name = name
        self.description = description
        self.parameters = parameters
    }
}

public func getRealtimeToolDefinitions(
    tools: [any AIToolProtocol]
) -> [RealtimeToolDefinition] {
    tools.map {
        RealtimeToolDefinition(
            name: $0.name, description: $0.description, parameters: $0.parameters
        )
    }
}

public struct RealtimeSessionConfig: Sendable {
    public struct AudioFormat: Sendable {
        public var type: String
        public var rate: Int?

        public init(type: String = "audio/pcm", rate: Int? = nil) {
            self.type = type
            self.rate = rate
        }
    }

    public struct Transcription: Sendable {
        public var model: String?
        public var language: String?
        public var prompt: String?

        public init(model: String? = nil, language: String? = nil, prompt: String? = nil) {
            self.model = model
            self.language = language
            self.prompt = prompt
        }
    }

    public struct TurnDetection: Sendable {
        public enum Kind: String, Sendable {
            case serverVAD = "server-vad"
            case semanticVAD = "semantic-vad"
            case disabled
        }

        public var type: Kind
        public var threshold: Double?
        public var silenceDurationMs: Int?
        public var prefixPaddingMs: Int?

        public init(
            type: Kind,
            threshold: Double? = nil,
            silenceDurationMs: Int? = nil,
            prefixPaddingMs: Int? = nil
        ) {
            self.type = type
            self.threshold = threshold
            self.silenceDurationMs = silenceDurationMs
            self.prefixPaddingMs = prefixPaddingMs
        }
    }

    public var instructions: String?
    public var voice: String?
    public var outputModalities: [String]?
    public var inputAudioFormat: AudioFormat?
    public var inputAudioTranscription: Transcription?
    public var outputAudioTranscription: Transcription?
    public var outputAudioFormat: AudioFormat?
    public var turnDetection: TurnDetection?
    public var tools: [RealtimeToolDefinition]?
    public var providerOptions: JSONValue?

    public init(
        instructions: String? = nil,
        voice: String? = nil,
        outputModalities: [String]? = nil,
        inputAudioFormat: AudioFormat? = nil,
        inputAudioTranscription: Transcription? = nil,
        outputAudioTranscription: Transcription? = nil,
        outputAudioFormat: AudioFormat? = nil,
        turnDetection: TurnDetection? = nil,
        tools: [RealtimeToolDefinition]? = nil,
        providerOptions: JSONValue? = nil
    ) {
        self.instructions = instructions
        self.voice = voice
        self.outputModalities = outputModalities
        self.inputAudioFormat = inputAudioFormat
        self.inputAudioTranscription = inputAudioTranscription
        self.outputAudioTranscription = outputAudioTranscription
        self.outputAudioFormat = outputAudioFormat
        self.turnDetection = turnDetection
        self.tools = tools
        self.providerOptions = providerOptions
    }
}

public struct RealtimeClientSecret: Sendable {
    public var token: String
    public var url: String
    public var expiresAt: Int?

    public init(token: String, url: String, expiresAt: Int? = nil) {
        self.token = token
        self.url = url
        self.expiresAt = expiresAt
    }
}

public struct RealtimeClientSecretOptions: Sendable {
    public var expiresAfterSeconds: Int?
    public var sessionConfig: RealtimeSessionConfig?

    public init(
        expiresAfterSeconds: Int? = nil, sessionConfig: RealtimeSessionConfig? = nil
    ) {
        self.expiresAfterSeconds = expiresAfterSeconds
        self.sessionConfig = sessionConfig
    }
}

public enum RealtimeConversationItem: Sendable {
    case textMessage(String)
    case audioMessage(base64Audio: String)
    case functionCallOutput(callID: String, name: String?, output: String)
}

public enum RealtimeClientEvent: Sendable {
    case sessionUpdate(RealtimeSessionConfig)
    case inputAudioAppend(base64Audio: String)
    case inputAudioCommit
    case inputAudioClear
    case conversationItemCreate(RealtimeConversationItem)
    case conversationItemTruncate(itemID: String, contentIndex: Int, audioEndMs: Int)
    case responseCreate(modalities: [String]? = nil, instructions: String? = nil)
    case responseCancel
}

public enum RealtimeServerEvent: Sendable {
    case sessionCreated(sessionID: String?, raw: JSONValue)
    case sessionUpdated(raw: JSONValue)
    case speechStarted(itemID: String?, raw: JSONValue)
    case speechStopped(itemID: String?, raw: JSONValue)
    case audioCommitted(itemID: String?, previousItemID: String?, raw: JSONValue)
    case conversationItemAdded(itemID: String, raw: JSONValue)
    case inputTranscriptionCompleted(itemID: String, transcript: String, raw: JSONValue)
    case responseCreated(responseID: String, raw: JSONValue)
    case responseDone(responseID: String, status: String, raw: JSONValue)
    case outputItemAdded(responseID: String, itemID: String, raw: JSONValue)
    case outputItemDone(responseID: String, itemID: String, raw: JSONValue)
    case contentPartAdded(responseID: String, itemID: String, raw: JSONValue)
    case contentPartDone(responseID: String, itemID: String, raw: JSONValue)
    case audioDelta(responseID: String, itemID: String, delta: String, raw: JSONValue)
    case audioDone(responseID: String, itemID: String, raw: JSONValue)
    case audioTranscriptDelta(responseID: String, itemID: String, delta: String, raw: JSONValue)
    case audioTranscriptDone(responseID: String, itemID: String, transcript: String?, raw: JSONValue)
    case textDelta(responseID: String, itemID: String, delta: String, raw: JSONValue)
    case textDone(responseID: String, itemID: String, text: String?, raw: JSONValue)
    case functionCallArgumentsDelta(
        responseID: String, itemID: String, callID: String, delta: String, raw: JSONValue
    )
    case functionCallArgumentsDone(
        responseID: String, itemID: String, callID: String,
        name: String, arguments: String, raw: JSONValue
    )
    case error(message: String, code: String?, raw: JSONValue)
    case custom(rawType: String, raw: JSONValue)
}

public struct RealtimeWebSocketConfig: Sendable {
    public var url: URL
    public var protocols: [String]

    public init(url: URL, protocols: [String] = []) {
        self.url = url
        self.protocols = protocols
    }
}

public protocol RealtimeModel: Sendable {
    var provider: String { get }
    var modelID: String { get }

    func createClientSecret(
        options: RealtimeClientSecretOptions
    ) async throws -> RealtimeClientSecret

    func webSocketConfig(token: String, url: String) -> RealtimeWebSocketConfig

    func parseServerEvent(_ raw: JSONValue) -> [RealtimeServerEvent]

    func serializeClientEvent(_ event: RealtimeClientEvent) -> JSONValue?

    func buildSessionConfig(_ config: RealtimeSessionConfig) -> JSONValue

    func healthCheckResponse(for raw: JSONValue) -> JSONValue?
}

public extension RealtimeModel {
    func healthCheckResponse(for raw: JSONValue) -> JSONValue? { nil }
}
