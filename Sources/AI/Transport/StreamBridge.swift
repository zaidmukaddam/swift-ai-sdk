import Foundation

public enum UIMessageStream {
    public static let headers: [String: String] = [
        "content-type": "text/event-stream",
        "cache-control": "no-cache",
        "connection": "keep-alive",
        "x-vercel-ai-ui-message-stream": "v1",
        "x-accel-buffering": "no"
    ]

    public static func chunks(
        from parts: AsyncThrowingStream<TextStreamPart, Error>,
        messageID: String? = nil,
        metadata: JSONValue? = nil,
        messageMetadata: (@Sendable (TextStreamPart) -> JSONValue?)? = nil
    ) -> AsyncThrowingStream<UIMessageChunk, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                var bridge = ChunkBridge()
                continuation.yield(.start(messageID: messageID, messageMetadata: metadata))
                do {
                    for try await part in parts {
                        for chunk in bridge.convert(part) { continuation.yield(chunk) }
                        if let value = messageMetadata?(part) {
                            continuation.yield(.messageMetadata(value))
                        }
                    }
                } catch {
                    for chunk in bridge.closeOpenParts() { continuation.yield(chunk) }
                    continuation.yield(.error(errorText: "\(error)"))
                    continuation.yield(.finish(finishReason: .error))
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    public static func encodeSSE(_ chunk: UIMessageChunk) throws -> String {
        let data = try JSONEncoder().encode(chunk.wire)
        return "data: \(String(decoding: data, as: UTF8.self))\n\n"
    }

    public static let doneSSE = "data: [DONE]\n\n"
}

private struct ChunkBridge {
    private var step = 0
    private var openTextID: String?
    private var openReasoningID: String?

    mutating func convert(_ part: TextStreamPart) -> [UIMessageChunk] {
        switch part {
        case .startStep(let index):
            step = index
            return [.startStep]

        case .textDelta(let delta):
            var chunks: [UIMessageChunk] = []
            if openTextID == nil {
                openTextID = "text-\(step)"
                chunks.append(.textStart(id: openTextID!))
            }
            chunks.append(.textDelta(id: openTextID!, delta: delta))
            return chunks

        case .reasoningDelta(let delta):
            var chunks: [UIMessageChunk] = []
            if openReasoningID == nil {
                openReasoningID = "reasoning-\(step)"
                chunks.append(.reasoningStart(id: openReasoningID!))
            }
            chunks.append(.reasoningDelta(id: openReasoningID!, delta: delta))
            return chunks

        case .toolInputStart(let id, let name):
            return [.toolInputStart(toolCallID: id, toolName: name)]

        case .toolInputDelta(let id, let partialJSON):
            return [.toolInputDelta(toolCallID: id, inputTextDelta: partialJSON)]

        case .toolCall(let call):
            return [.toolInputAvailable(
                toolCallID: call.id, toolName: call.name, input: call.arguments
            )]

        case .toolResult(let result):
            if result.denied {
                return [.toolOutputDenied(toolCallID: result.toolCallID)]
            }
            if result.isError {
                return [.toolOutputError(
                    toolCallID: result.toolCallID,
                    errorText: result.output.stringValue ?? "\(result.output)"
                )]
            }
            return [.toolOutputAvailable(toolCallID: result.toolCallID, output: result.output)]

        case .toolApprovalRequest(let request):
            return [.toolApprovalRequest(
                approvalID: request.approvalID, toolCallID: request.call.id
            )]

        case .source(let source):
            return [.sourceURL(sourceID: source.id, url: source.url, title: source.title)]

        case .providerMetadata:
            return []

        case .finishStep:
            var chunks = closeOpenParts()
            chunks.append(.finishStep)
            return chunks

        case .finish(let finishReason, _):
            var chunks = closeOpenParts()
            chunks.append(.finish(finishReason: finishReason))
            return chunks
        }
    }

    mutating func closeOpenParts() -> [UIMessageChunk] {
        var chunks: [UIMessageChunk] = []
        if let id = openTextID {
            chunks.append(.textEnd(id: id))
            openTextID = nil
        }
        if let id = openReasoningID {
            chunks.append(.reasoningEnd(id: id))
            openReasoningID = nil
        }
        return chunks
    }
}

private func contentPart(from file: FileUIPart) -> ContentPart? {
    let isImage = file.mediaType.hasPrefix("image/")
    if let (data, mediaType) = decodeDataURL(file.url) {
        return isImage
            ? .image(ImageContent(data: data, mediaType: mediaType ?? file.mediaType))
            : .file(FileContent(
                data: data, mediaType: mediaType ?? file.mediaType, filename: file.filename
            ))
    }
    guard let url = URL(string: file.url) else { return nil }
    return isImage
        ? .image(ImageContent(url: url, mediaType: file.mediaType))
        : .file(FileContent(url: url, mediaType: file.mediaType, filename: file.filename))
}

private func decodeDataURL(_ string: String) -> (Data, String?)? {
    guard string.hasPrefix("data:"),
          let comma = string.firstIndex(of: ",") else { return nil }
    let header = String(string[string.index(string.startIndex, offsetBy: 5)..<comma])
    guard let data = Data(base64Encoded: String(string[string.index(after: comma)...]))
    else { return nil }
    let mediaType = header.split(separator: ";").first.map(String.init)
    return (data, mediaType?.isEmpty == false ? mediaType : nil)
}

public func convertToModelMessages(_ uiMessages: [UIMessage]) -> [Message] {
    var out: [Message] = []
    for uiMessage in uiMessages {
        switch uiMessage.role {
        case .system:
            let text = uiMessage.text
            if !text.isEmpty { out.append(.system(text)) }

        case .user:
            var userParts: [ContentPart] = []
            for part in uiMessage.parts {
                switch part {
                case .text(let text) where !text.text.isEmpty:
                    userParts.append(.text(text.text))
                case .file(let file):
                    if let converted = contentPart(from: file) {
                        userParts.append(converted)
                    }
                default:
                    break
                }
            }
            if !userParts.isEmpty {
                out.append(Message(role: .user, content: userParts))
            }

        case .assistant:
            var assistantParts: [ContentPart] = []
            var toolTurnParts: [ContentPart] = []
            for part in uiMessage.parts {
                switch part {
                case .text(let text) where !text.text.isEmpty:
                    assistantParts.append(.text(text.text))
                case .tool(let tool):
                    guard tool.state != .inputStreaming else { continue }
                    assistantParts.append(.toolCall(ToolCall(
                        id: tool.toolCallID, name: tool.toolName,
                        arguments: tool.input ?? .object([:])
                    )))
                    switch tool.state {
                    case .outputAvailable:
                        toolTurnParts.append(.toolResult(ToolResult(
                            toolCallID: tool.toolCallID, name: tool.toolName,
                            output: tool.output ?? .null
                        )))
                    case .outputError:
                        toolTurnParts.append(.toolResult(ToolResult(
                            toolCallID: tool.toolCallID, name: tool.toolName,
                            output: .string(tool.errorText ?? "Tool execution failed"),
                            isError: true
                        )))
                    case .outputDenied:
                        toolTurnParts.append(.toolResult(ToolResult(
                            toolCallID: tool.toolCallID, name: tool.toolName,
                            output: .string(tool.approval?.reason ?? "Tool execution denied."),
                            denied: true
                        )))
                    case .approvalResponded:
                        if let approval = tool.approval, let approved = approval.approved {
                            toolTurnParts.append(.toolApprovalResponse(ToolApprovalResponse(
                                approvalID: approval.id,
                                toolCallID: tool.toolCallID,
                                approved: approved,
                                reason: approval.reason
                            )))
                        }
                    default:
                        break
                    }
                default:
                    break
                }
            }
            if !assistantParts.isEmpty {
                out.append(Message(role: .assistant, content: assistantParts))
            }
            if !toolTurnParts.isEmpty {
                out.append(Message(role: .tool, content: toolTurnParts))
            }
        }
    }
    return out
}
