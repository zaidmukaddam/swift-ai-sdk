import Foundation

public struct Source: Sendable, Hashable {
    public var id: String
    public var url: String
    public var title: String?

    public init(id: String, url: String, title: String? = nil) {
        self.id = id
        self.url = url
        self.title = title
    }
}

public enum StreamPart: Sendable {
    case textDelta(String)
    case reasoningDelta(String)
    case toolCallStart(id: String, name: String)
    case toolArgumentsDelta(id: String, partialJSON: String)
    case toolCall(ToolCall)
    case toolResult(ToolResult)
    case source(Source)
    case providerMetadata(JSONValue)
    case finish(reason: FinishReason, usage: Usage)
}

public enum ToolChoice: Sendable, Hashable {
    case auto
    case none
    case required
    case tool(String)
}

public enum ResponseFormat: Sendable {
    case text
    case json(schema: JSONValue, name: String = "response", description: String? = nil)
    case jsonNoSchema
}

public enum ReasoningEffort: String, Sendable, Codable {
    case providerDefault = "provider-default"
    case none
    case minimal
    case low
    case medium
    case high
    case xhigh

    public var isCustom: Bool { self != .providerDefault }

    public func budget(maxOutputTokens: Int, maxBudget: Int, minBudget: Int = 1024) -> Int? {
        let fraction: Double
        switch self {
        case .providerDefault, .none: return nil
        case .minimal: fraction = 0.02
        case .low: fraction = 0.1
        case .medium: fraction = 0.3
        case .high: fraction = 0.6
        case .xhigh: fraction = 0.9
        }
        let raw = Int((Double(maxOutputTokens) * fraction).rounded())
        return Swift.min(maxBudget, Swift.max(minBudget, raw))
    }
}

public struct LanguageModelRequest: Sendable {
    public var messages: [Message]
    public var tools: [any AIToolProtocol]
    public var toolChoice: ToolChoice
    public var maxOutputTokens: Int
    public var temperature: Double?
    public var topP: Double?
    public var topK: Int?
    public var presencePenalty: Double?
    public var frequencyPenalty: Double?
    public var seed: Int?
    public var reasoning: ReasoningEffort
    public var stopSequences: [String]
    public var responseFormat: ResponseFormat
    public var providerOptions: JSONValue?

    public init(
        messages: [Message],
        tools: [any AIToolProtocol] = [],
        toolChoice: ToolChoice = .auto,
        maxOutputTokens: Int = 1024,
        temperature: Double? = nil,
        topP: Double? = nil,
        topK: Int? = nil,
        presencePenalty: Double? = nil,
        frequencyPenalty: Double? = nil,
        seed: Int? = nil,
        reasoning: ReasoningEffort = .providerDefault,
        stopSequences: [String] = [],
        responseFormat: ResponseFormat = .text,
        providerOptions: JSONValue? = nil
    ) {
        self.messages = messages
        self.tools = tools
        self.toolChoice = toolChoice
        self.maxOutputTokens = maxOutputTokens
        self.temperature = temperature
        self.topP = topP
        self.topK = topK
        self.presencePenalty = presencePenalty
        self.frequencyPenalty = frequencyPenalty
        self.seed = seed
        self.reasoning = reasoning
        self.stopSequences = stopSequences
        self.responseFormat = responseFormat
        self.providerOptions = providerOptions
    }
}

public protocol LanguageModel: Sendable {
    var provider: String { get }
    var modelID: String { get }
    func stream(_ request: LanguageModelRequest) async throws -> AsyncThrowingStream<StreamPart, Error>
}
