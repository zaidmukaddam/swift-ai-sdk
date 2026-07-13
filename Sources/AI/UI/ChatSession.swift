#if canImport(Observation)
import Foundation
import Observation

@available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, visionOS 1.0, *)
@Observable @MainActor
public final class ChatSession {
    public enum Status: Sendable, Equatable {
        case ready
        case submitted
        case streaming
        case error(String)
    }

    public let id: String
    public private(set) var messages: [UIMessage]
    public private(set) var status: Status = .ready

    public var isLoading: Bool { status == .submitted || status == .streaming }

    private let transport: any ChatTransport
    private var streamTask: Task<Void, Never>?

    public init(
        transport: any ChatTransport,
        id: String = UUID().uuidString,
        messages: [UIMessage] = []
    ) {
        self.transport = transport
        self.id = id
        self.messages = messages
    }

    public func send(_ text: String) {
        sendMessage(.user(text))
    }

    public func sendMessage(_ message: UIMessage) {
        messages.append(message)
        start(ChatRequest(chatID: id, messages: messages, trigger: .submitMessage))
    }

    public func regenerate() {
        guard let lastAssistant = messages.last(where: { $0.role == .assistant }) else { return }
        messages.removeAll { $0.id == lastAssistant.id }
        start(ChatRequest(
            chatID: id, messages: messages,
            trigger: .regenerateMessage, messageID: lastAssistant.id
        ))
    }

    public func addToolResult(toolCallID: String, result: JSONValue) {
        guard let messageIndex = messages.lastIndex(where: { message in
            message.parts.contains {
                if case .tool(let tool) = $0 { return tool.toolCallID == toolCallID }
                return false
            }
        }) else { return }

        var message = messages[messageIndex]
        for (partIndex, part) in message.parts.enumerated() {
            guard case .tool(var tool) = part, tool.toolCallID == toolCallID else { continue }
            tool.state = .outputAvailable
            tool.output = result
            message.parts[partIndex] = .tool(tool)
        }
        messages[messageIndex] = message

        let stillPending = messages[messageIndex].parts.contains {
            if case .tool(let tool) = $0 { return tool.state == .inputAvailable }
            return false
        }
        if !stillPending {
            start(ChatRequest(chatID: id, messages: messages, trigger: .submitMessage))
        }
    }

    public func addToolApprovalResponse(
        approvalID: String, approved: Bool, reason: String? = nil
    ) {
        guard let messageIndex = messages.lastIndex(where: { message in
            message.parts.contains {
                if case .tool(let tool) = $0 { return tool.approval?.id == approvalID }
                return false
            }
        }) else { return }

        var message = messages[messageIndex]
        for (partIndex, part) in message.parts.enumerated() {
            guard case .tool(var tool) = part, tool.approval?.id == approvalID else { continue }
            tool.state = .approvalResponded
            tool.approval = ToolApproval(id: approvalID, approved: approved, reason: reason)
            message.parts[partIndex] = .tool(tool)
        }
        messages[messageIndex] = message

        let stillPending = messages[messageIndex].parts.contains {
            if case .tool(let tool) = $0 { return tool.state == .approvalRequested }
            return false
        }
        if !stillPending {
            start(ChatRequest(chatID: id, messages: messages, trigger: .submitMessage))
        }
    }

    public func resumeStream() {
        streamTask?.cancel()
        status = .submitted

        streamTask = Task { [transport] in
            do {
                guard let chunks = try await transport.reconnectToStream(chatID: id) else {
                    status = .ready
                    return
                }
                try await consume(chunks)
            } catch is CancellationError {
                status = .ready
            } catch {
                status = .error("\(error)")
            }
        }
    }

    public func stop() {
        streamTask?.cancel()
        streamTask = nil
        if isLoading { status = .ready }
    }

    public func setMessages(_ newMessages: [UIMessage]) {
        stop()
        messages = newMessages
    }

    private func start(_ request: ChatRequest) {
        streamTask?.cancel()
        status = .submitted

        streamTask = Task { [transport] in
            do {
                try await consume(transport.sendMessages(request))
            } catch is CancellationError {
                status = .ready
            } catch {
                status = .error("\(error)")
            }
        }
    }

    private func consume(_ chunks: AsyncThrowingStream<UIMessageChunk, Error>) async throws {
        var reducer = UIMessageReducer()
        var assistantIndex: Int?

        for try await chunk in chunks {
            if Task.isCancelled { break }
            reducer.apply(chunk)
            if status == .submitted { status = .streaming }

            if let index = assistantIndex {
                messages[index] = reducer.message
            } else {
                assistantIndex = messages.count
                messages.append(reducer.message)
            }
        }

        if let errorText = reducer.errorText {
            status = .error(errorText)
        } else if !Task.isCancelled {
            status = .ready
        }
    }
}
#endif
