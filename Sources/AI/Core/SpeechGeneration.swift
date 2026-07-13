import Foundation

public protocol SpeechModel: Sendable {
    var provider: String { get }
    var modelID: String { get }
    func generateSpeech(_ request: SpeechModelRequest) async throws -> SpeechModelResponse
}

public struct SpeechModelRequest: Sendable {
    public var text: String
    public var voice: String?
    public var instructions: String?
    public var speed: Double?
    public var outputFormat: String?
    public var providerOptions: JSONValue?

    public init(
        text: String,
        voice: String? = nil,
        instructions: String? = nil,
        speed: Double? = nil,
        outputFormat: String? = nil,
        providerOptions: JSONValue? = nil
    ) {
        self.text = text
        self.voice = voice
        self.instructions = instructions
        self.speed = speed
        self.outputFormat = outputFormat
        self.providerOptions = providerOptions
    }
}

public struct SpeechModelResponse: Sendable {
    public var audio: Data
    public var mediaType: String

    public init(audio: Data, mediaType: String) {
        self.audio = audio
        self.mediaType = mediaType
    }
}

public struct GenerateSpeechResult: Sendable {
    public var audio: Data
    public var mediaType: String
}

public func generateSpeech(
    model: any SpeechModel,
    text: String,
    voice: String? = nil,
    instructions: String? = nil,
    speed: Double? = nil,
    outputFormat: String? = nil,
    providerOptions: JSONValue? = nil,
    maxRetries: Int = 2
) async throws -> GenerateSpeechResult {
    let request = SpeechModelRequest(
        text: text,
        voice: voice,
        instructions: instructions,
        speed: speed,
        outputFormat: outputFormat,
        providerOptions: providerOptions
    )
    let response = try await Retry.withRetries(maxRetries) {
        try await model.generateSpeech(request)
    }
    guard !response.audio.isEmpty else {
        throw AIError.decoding("Speech response contained no audio")
    }
    return GenerateSpeechResult(audio: response.audio, mediaType: response.mediaType)
}
