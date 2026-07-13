import Foundation

public struct UIMessageReducer: Sendable {
    public private(set) var message: UIMessage
    public private(set) var isFinished = false
    public private(set) var finishReason: FinishReason?
    public private(set) var errorText: String?

    private var textParts: [String: Int] = [:]
    private var reasoningParts: [String: Int] = [:]
    private var toolParts: [String: Int] = [:]
    private var toolInputBuffers: [String: String] = [:]
    private var approvalToolCalls: [String: String] = [:]
    private var dataParts: [String: Int] = [:]

    public init(messageID: String = UUID().uuidString) {
        self.message = UIMessage(id: messageID, role: .assistant, parts: [])
    }

    public init(message: UIMessage) {
        self.message = message
        reindex()
    }

    public mutating func apply(_ chunk: UIMessageChunk) {
        switch chunk {
        case .start(let messageID, let messageMetadata):
            if let messageID { message.id = messageID }
            if let messageMetadata { applyMetadata(messageMetadata) }

        case .textStart(let id):
            textParts[id] = message.parts.count
            message.parts.append(.text(TextUIPart(text: "", state: .streaming)))

        case .textDelta(let id, let delta):
            guard let index = textParts[id], case .text(var part) = message.parts[index]
            else { return }
            part.text += delta
            message.parts[index] = .text(part)

        case .textEnd(let id):
            guard let index = textParts[id], case .text(var part) = message.parts[index]
            else { return }
            part.state = .done
            message.parts[index] = .text(part)

        case .reasoningStart(let id):
            reasoningParts[id] = message.parts.count
            message.parts.append(.reasoning(ReasoningUIPart(text: "", state: .streaming)))

        case .reasoningDelta(let id, let delta):
            guard let index = reasoningParts[id], case .reasoning(var part) = message.parts[index]
            else { return }
            part.text += delta
            message.parts[index] = .reasoning(part)

        case .reasoningEnd(let id):
            guard let index = reasoningParts[id], case .reasoning(var part) = message.parts[index]
            else { return }
            part.state = .done
            message.parts[index] = .reasoning(part)

        case .toolInputStart(let toolCallID, let toolName, let providerExecuted, let dynamic):
            upsertTool(toolCallID) { part in
                part.toolName = toolName
                part.state = .inputStreaming
                part.providerExecuted = providerExecuted
                part.isDynamic = dynamic ?? false
            } create: {
                ToolUIPart(
                    toolName: toolName, toolCallID: toolCallID, state: .inputStreaming,
                    providerExecuted: providerExecuted, isDynamic: dynamic ?? false
                )
            }

        case .toolInputDelta(let toolCallID, let inputTextDelta):
            let buffer = (toolInputBuffers[toolCallID] ?? "") + inputTextDelta
            toolInputBuffers[toolCallID] = buffer
            let partial = PartialJSON.parse(buffer)
            upsertTool(toolCallID) { part in
                if let partial { part.input = partial }
            } create: {
                ToolUIPart(toolName: "", toolCallID: toolCallID, state: .inputStreaming, input: partial)
            }

        case .toolInputAvailable(let toolCallID, let toolName, let input, let providerExecuted, let dynamic):
            toolInputBuffers[toolCallID] = nil
            upsertTool(toolCallID) { part in
                part.toolName = toolName
                part.state = .inputAvailable
                part.input = input
                part.providerExecuted = providerExecuted
                part.isDynamic = dynamic ?? part.isDynamic
            } create: {
                ToolUIPart(
                    toolName: toolName, toolCallID: toolCallID, state: .inputAvailable,
                    input: input, providerExecuted: providerExecuted, isDynamic: dynamic ?? false
                )
            }

        case .toolInputError(let toolCallID, let toolName, let input, let errorText, let dynamic):
            toolInputBuffers[toolCallID] = nil
            upsertTool(toolCallID) { part in
                part.toolName = toolName
                part.state = .outputError
                if let input { part.input = input }
                part.errorText = errorText
                part.isDynamic = dynamic ?? part.isDynamic
            } create: {
                ToolUIPart(
                    toolName: toolName, toolCallID: toolCallID, state: .outputError,
                    input: input, errorText: errorText, isDynamic: dynamic ?? false
                )
            }

        case .toolOutputAvailable(let toolCallID, let output, let providerExecuted, _, let dynamic):
            upsertTool(toolCallID) { part in
                part.state = .outputAvailable
                part.output = output
                if let providerExecuted { part.providerExecuted = providerExecuted }
                part.isDynamic = dynamic ?? part.isDynamic
            } create: {
                ToolUIPart(
                    toolName: "", toolCallID: toolCallID, state: .outputAvailable,
                    output: output, providerExecuted: providerExecuted, isDynamic: dynamic ?? false
                )
            }

        case .toolOutputError(let toolCallID, let errorText, let dynamic):
            upsertTool(toolCallID) { part in
                part.state = .outputError
                part.errorText = errorText
                part.isDynamic = dynamic ?? part.isDynamic
            } create: {
                ToolUIPart(
                    toolName: "", toolCallID: toolCallID, state: .outputError,
                    errorText: errorText, isDynamic: dynamic ?? false
                )
            }

        case .toolApprovalRequest(let approvalID, let toolCallID):
            approvalToolCalls[approvalID] = toolCallID
            upsertTool(toolCallID) { part in
                part.state = .approvalRequested
                part.approval = ToolApproval(id: approvalID)
            } create: {
                ToolUIPart(
                    toolName: "", toolCallID: toolCallID, state: .approvalRequested,
                    approval: ToolApproval(id: approvalID)
                )
            }

        case .toolApprovalResponse(let approvalID, let approved, let reason):
            guard let toolCallID = approvalToolCalls[approvalID] else { return }
            upsertTool(toolCallID) { part in
                part.state = .approvalResponded
                part.approval = ToolApproval(id: approvalID, approved: approved, reason: reason)
            } create: {
                ToolUIPart(
                    toolName: "", toolCallID: toolCallID, state: .approvalResponded,
                    approval: ToolApproval(id: approvalID, approved: approved, reason: reason)
                )
            }

        case .toolOutputDenied(let toolCallID):
            upsertTool(toolCallID) { part in
                part.state = .outputDenied
                if var approval = part.approval {
                    approval.approved = false
                    part.approval = approval
                }
            } create: {
                ToolUIPart(toolName: "", toolCallID: toolCallID, state: .outputDenied)
            }

        case .sourceURL(let sourceID, let url, let title):
            message.parts.append(.sourceURL(SourceURLUIPart(sourceID: sourceID, url: url, title: title)))

        case .sourceDocument(let sourceID, let mediaType, let title, let filename):
            message.parts.append(.sourceDocument(SourceDocumentUIPart(
                sourceID: sourceID, mediaType: mediaType, title: title, filename: filename
            )))

        case .file(let url, let mediaType):
            message.parts.append(.file(FileUIPart(url: url, mediaType: mediaType)))

        case .data(let name, let id, let data, let transient):
            if transient == true { return }
            if let id {
                let key = "\(name)\n\(id)"
                if let index = dataParts[key], case .data(var part) = message.parts[index] {
                    part.data = data
                    message.parts[index] = .data(part)
                } else {
                    dataParts[key] = message.parts.count
                    message.parts.append(.data(DataUIPart(name: name, id: id, data: data)))
                }
            } else {
                message.parts.append(.data(DataUIPart(name: name, data: data)))
            }

        case .startStep:
            message.parts.append(.stepStart)

        case .finishStep:
            break

        case .finish(let finishReason, let messageMetadata):
            isFinished = true
            self.finishReason = finishReason
            if let messageMetadata { applyMetadata(messageMetadata) }

        case .abort:
            isFinished = true

        case .error(let errorText):
            self.errorText = errorText

        case .messageMetadata(let metadata):
            applyMetadata(metadata)
        }
    }

    private mutating func applyMetadata(_ update: JSONValue) {
        message.metadata = Self.deepMerge(message.metadata, update)
    }

    static func deepMerge(_ base: JSONValue?, _ update: JSONValue) -> JSONValue {
        guard case .object(var merged) = base ?? .null, case .object(let overrides) = update
        else { return update }
        for (key, value) in overrides {
            merged[key] = deepMerge(merged[key], value)
        }
        return .object(merged)
    }

    private mutating func upsertTool(
        _ toolCallID: String,
        update: (inout ToolUIPart) -> Void,
        create: () -> ToolUIPart
    ) {
        if let index = toolParts[toolCallID], case .tool(var part) = message.parts[index] {
            update(&part)
            message.parts[index] = .tool(part)
        } else {
            toolParts[toolCallID] = message.parts.count
            message.parts.append(.tool(create()))
        }
    }

    private mutating func reindex() {
        for (index, part) in message.parts.enumerated() {
            if case .tool(let tool) = part { toolParts[tool.toolCallID] = index }
            if case .data(let data) = part, let id = data.id {
                dataParts["\(data.name)\n\(id)"] = index
            }
        }
    }
}
