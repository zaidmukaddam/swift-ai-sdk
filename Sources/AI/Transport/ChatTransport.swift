import Foundation

public enum ChatTrigger: String, Sendable, Codable, Hashable {
    case submitMessage = "submit-message"
    case regenerateMessage = "regenerate-message"
}

public struct ChatRequest: Sendable {
    public var chatID: String
    public var messages: [UIMessage]
    public var trigger: ChatTrigger
    public var messageID: String?

    public init(
        chatID: String,
        messages: [UIMessage],
        trigger: ChatTrigger = .submitMessage,
        messageID: String? = nil
    ) {
        self.chatID = chatID
        self.messages = messages
        self.trigger = trigger
        self.messageID = messageID
    }
}

public protocol ChatTransport: Sendable {
    func sendMessages(_ request: ChatRequest) async throws -> AsyncThrowingStream<UIMessageChunk, Error>

    func reconnectToStream(chatID: String) async throws -> AsyncThrowingStream<UIMessageChunk, Error>?
}

public extension ChatTransport {
    func reconnectToStream(chatID: String) async throws -> AsyncThrowingStream<UIMessageChunk, Error>? {
        nil
    }
}
