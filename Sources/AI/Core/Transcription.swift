import Foundation

public protocol TranscriptionModel: Sendable {
    var provider: String { get }
    var modelID: String { get }
    func transcribe(_ request: TranscriptionModelRequest) async throws -> TranscriptionModelResponse
}

public struct TranscriptionModelRequest: Sendable {
    public var audio: Data
    public var mediaType: String
    public var providerOptions: JSONValue?

    public init(audio: Data, mediaType: String, providerOptions: JSONValue? = nil) {
        self.audio = audio
        self.mediaType = mediaType
        self.providerOptions = providerOptions
    }
}

public struct TranscriptionSegment: Sendable, Hashable {
    public var text: String
    public var startSecond: Double
    public var endSecond: Double

    public init(text: String, startSecond: Double, endSecond: Double) {
        self.text = text
        self.startSecond = startSecond
        self.endSecond = endSecond
    }
}

public struct TranscriptionModelResponse: Sendable {
    public var text: String
    public var segments: [TranscriptionSegment]
    public var language: String?
    public var durationInSeconds: Double?

    public init(
        text: String,
        segments: [TranscriptionSegment] = [],
        language: String? = nil,
        durationInSeconds: Double? = nil
    ) {
        self.text = text
        self.segments = segments
        self.language = language
        self.durationInSeconds = durationInSeconds
    }
}

public struct TranscriptionResult: Sendable {
    public var text: String
    public var segments: [TranscriptionSegment]
    public var language: String?
    public var durationInSeconds: Double?
}

public func transcribe(
    model: any TranscriptionModel,
    audio: Data,
    mediaType: String,
    providerOptions: JSONValue? = nil,
    maxRetries: Int = 2
) async throws -> TranscriptionResult {
    let request = TranscriptionModelRequest(
        audio: audio,
        mediaType: mediaType,
        providerOptions: providerOptions
    )
    let response = try await Retry.withRetries(maxRetries) {
        try await model.transcribe(request)
    }
    guard !response.text.isEmpty else {
        throw AIError.decoding("Transcription response contained no text")
    }
    return TranscriptionResult(
        text: response.text,
        segments: response.segments,
        language: response.language,
        durationInSeconds: response.durationInSeconds
    )
}
