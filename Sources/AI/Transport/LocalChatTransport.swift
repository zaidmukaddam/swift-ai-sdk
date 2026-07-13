import Foundation

public struct LocalChatTransport: ChatTransport {
    public var model: any LanguageModel
    public var tools: [any AIToolProtocol]
    public var system: String?
    public var maxOutputTokens: Int
    public var temperature: Double?
    public var maxSteps: Int

    public init(
        model: any LanguageModel,
        tools: [any AIToolProtocol] = [],
        system: String? = nil,
        maxOutputTokens: Int = 1024,
        temperature: Double? = nil,
        maxSteps: Int = 8
    ) {
        self.model = model
        self.tools = tools
        self.system = system
        self.maxOutputTokens = maxOutputTokens
        self.temperature = temperature
        self.maxSteps = maxSteps
    }

    public func sendMessages(
        _ request: ChatRequest
    ) async throws -> AsyncThrowingStream<UIMessageChunk, Error> {
        var messages = request.messages
        if request.trigger == .regenerateMessage {
            if let targetID = request.messageID,
               let index = messages.firstIndex(where: { $0.id == targetID }) {
                messages = Array(messages[..<index])
            } else if messages.last?.role == .assistant {
                messages.removeLast()
            }
        }

        let result = streamText(
            model: model,
            messages: convertToModelMessages(messages),
            system: system,
            tools: tools,
            maxOutputTokens: maxOutputTokens,
            temperature: temperature,
            maxSteps: maxSteps
        )
        return UIMessageStream.chunks(from: result.fullStream, messageID: UUID().uuidString)
    }
}
