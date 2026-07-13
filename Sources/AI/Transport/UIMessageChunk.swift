import Foundation

public enum UIMessageChunk: Sendable, Hashable {
    case textStart(id: String)
    case textDelta(id: String, delta: String)
    case textEnd(id: String)
    case reasoningStart(id: String)
    case reasoningDelta(id: String, delta: String)
    case reasoningEnd(id: String)
    case error(errorText: String)
    case toolInputStart(toolCallID: String, toolName: String, providerExecuted: Bool? = nil, dynamic: Bool? = nil)
    case toolInputDelta(toolCallID: String, inputTextDelta: String)
    case toolInputAvailable(toolCallID: String, toolName: String, input: JSONValue, providerExecuted: Bool? = nil, dynamic: Bool? = nil)
    case toolInputError(toolCallID: String, toolName: String, input: JSONValue?, errorText: String, dynamic: Bool? = nil)
    case toolOutputAvailable(toolCallID: String, output: JSONValue, providerExecuted: Bool? = nil, preliminary: Bool? = nil, dynamic: Bool? = nil)
    case toolOutputError(toolCallID: String, errorText: String, dynamic: Bool? = nil)
    case toolApprovalRequest(approvalID: String, toolCallID: String)
    case toolApprovalResponse(approvalID: String, approved: Bool, reason: String? = nil)
    case toolOutputDenied(toolCallID: String)
    case sourceURL(sourceID: String, url: String, title: String? = nil)
    case sourceDocument(sourceID: String, mediaType: String, title: String, filename: String? = nil)
    case file(url: String, mediaType: String)
    case data(name: String, id: String? = nil, data: JSONValue, transient: Bool? = nil)
    case startStep
    case finishStep
    case start(messageID: String? = nil, messageMetadata: JSONValue? = nil)
    case finish(finishReason: FinishReason? = nil, messageMetadata: JSONValue? = nil)
    case abort(reason: String? = nil)
    case messageMetadata(JSONValue)
}

extension FinishReason {
    public var wireValue: String {
        switch self {
        case .stop: "stop"
        case .length: "length"
        case .toolCalls: "tool-calls"
        case .contentFilter: "content-filter"
        case .error: "error"
        case .other: "other"
        }
    }

    public init?(wireValue: String) {
        switch wireValue {
        case "stop": self = .stop
        case "length": self = .length
        case "tool-calls": self = .toolCalls
        case "content-filter": self = .contentFilter
        case "error": self = .error
        case "other": self = .other
        default: return nil
        }
    }
}

extension UIMessageChunk {
    public var wire: JSONValue {
        var object: [String: JSONValue]
        switch self {
        case .textStart(let id):
            object = ["type": "text-start", "id": .string(id)]
        case .textDelta(let id, let delta):
            object = ["type": "text-delta", "id": .string(id), "delta": .string(delta)]
        case .textEnd(let id):
            object = ["type": "text-end", "id": .string(id)]
        case .reasoningStart(let id):
            object = ["type": "reasoning-start", "id": .string(id)]
        case .reasoningDelta(let id, let delta):
            object = ["type": "reasoning-delta", "id": .string(id), "delta": .string(delta)]
        case .reasoningEnd(let id):
            object = ["type": "reasoning-end", "id": .string(id)]
        case .error(let errorText):
            object = ["type": "error", "errorText": .string(errorText)]
        case .toolInputStart(let toolCallID, let toolName, let providerExecuted, let dynamic):
            object = [
                "type": "tool-input-start",
                "toolCallId": .string(toolCallID),
                "toolName": .string(toolName)
            ]
            if let providerExecuted { object["providerExecuted"] = .bool(providerExecuted) }
            if let dynamic { object["dynamic"] = .bool(dynamic) }
        case .toolInputDelta(let toolCallID, let inputTextDelta):
            object = [
                "type": "tool-input-delta",
                "toolCallId": .string(toolCallID),
                "inputTextDelta": .string(inputTextDelta)
            ]
        case .toolInputAvailable(let toolCallID, let toolName, let input, let providerExecuted, let dynamic):
            object = [
                "type": "tool-input-available",
                "toolCallId": .string(toolCallID),
                "toolName": .string(toolName),
                "input": input
            ]
            if let providerExecuted { object["providerExecuted"] = .bool(providerExecuted) }
            if let dynamic { object["dynamic"] = .bool(dynamic) }
        case .toolInputError(let toolCallID, let toolName, let input, let errorText, let dynamic):
            object = [
                "type": "tool-input-error",
                "toolCallId": .string(toolCallID),
                "toolName": .string(toolName),
                "errorText": .string(errorText)
            ]
            if let input { object["input"] = input }
            if let dynamic { object["dynamic"] = .bool(dynamic) }
        case .toolOutputAvailable(let toolCallID, let output, let providerExecuted, let preliminary, let dynamic):
            object = [
                "type": "tool-output-available",
                "toolCallId": .string(toolCallID),
                "output": output
            ]
            if let providerExecuted { object["providerExecuted"] = .bool(providerExecuted) }
            if let preliminary { object["preliminary"] = .bool(preliminary) }
            if let dynamic { object["dynamic"] = .bool(dynamic) }
        case .toolOutputError(let toolCallID, let errorText, let dynamic):
            object = [
                "type": "tool-output-error",
                "toolCallId": .string(toolCallID),
                "errorText": .string(errorText)
            ]
            if let dynamic { object["dynamic"] = .bool(dynamic) }
        case .toolApprovalRequest(let approvalID, let toolCallID):
            object = [
                "type": "tool-approval-request",
                "approvalId": .string(approvalID),
                "toolCallId": .string(toolCallID)
            ]
        case .toolApprovalResponse(let approvalID, let approved, let reason):
            object = [
                "type": "tool-approval-response",
                "approvalId": .string(approvalID),
                "approved": .bool(approved)
            ]
            if let reason { object["reason"] = .string(reason) }
        case .toolOutputDenied(let toolCallID):
            object = ["type": "tool-output-denied", "toolCallId": .string(toolCallID)]
        case .sourceURL(let sourceID, let url, let title):
            object = ["type": "source-url", "sourceId": .string(sourceID), "url": .string(url)]
            if let title { object["title"] = .string(title) }
        case .sourceDocument(let sourceID, let mediaType, let title, let filename):
            object = [
                "type": "source-document",
                "sourceId": .string(sourceID),
                "mediaType": .string(mediaType),
                "title": .string(title)
            ]
            if let filename { object["filename"] = .string(filename) }
        case .file(let url, let mediaType):
            object = ["type": "file", "url": .string(url), "mediaType": .string(mediaType)]
        case .data(let name, let id, let data, let transient):
            object = ["type": .string("data-\(name)"), "data": data]
            if let id { object["id"] = .string(id) }
            if let transient { object["transient"] = .bool(transient) }
        case .startStep:
            object = ["type": "start-step"]
        case .finishStep:
            object = ["type": "finish-step"]
        case .start(let messageID, let messageMetadata):
            object = ["type": "start"]
            if let messageID { object["messageId"] = .string(messageID) }
            if let messageMetadata { object["messageMetadata"] = messageMetadata }
        case .finish(let finishReason, let messageMetadata):
            object = ["type": "finish"]
            if let finishReason { object["finishReason"] = .string(finishReason.wireValue) }
            if let messageMetadata { object["messageMetadata"] = messageMetadata }
        case .abort(let reason):
            object = ["type": "abort"]
            if let reason { object["reason"] = .string(reason) }
        case .messageMetadata(let metadata):
            object = ["type": "message-metadata", "messageMetadata": metadata]
        }
        return .object(object)
    }

    public init?(wire: JSONValue) {
        guard let type = wire["type"]?.stringValue else { return nil }
        switch type {
        case "text-start":
            guard let id = wire["id"]?.stringValue else { return nil }
            self = .textStart(id: id)
        case "text-delta":
            guard let id = wire["id"]?.stringValue,
                  let delta = wire["delta"]?.stringValue else { return nil }
            self = .textDelta(id: id, delta: delta)
        case "text-end":
            guard let id = wire["id"]?.stringValue else { return nil }
            self = .textEnd(id: id)
        case "reasoning-start":
            guard let id = wire["id"]?.stringValue else { return nil }
            self = .reasoningStart(id: id)
        case "reasoning-delta":
            guard let id = wire["id"]?.stringValue,
                  let delta = wire["delta"]?.stringValue else { return nil }
            self = .reasoningDelta(id: id, delta: delta)
        case "reasoning-end":
            guard let id = wire["id"]?.stringValue else { return nil }
            self = .reasoningEnd(id: id)
        case "error":
            guard let errorText = wire["errorText"]?.stringValue else { return nil }
            self = .error(errorText: errorText)
        case "tool-input-start":
            guard let toolCallID = wire["toolCallId"]?.stringValue,
                  let toolName = wire["toolName"]?.stringValue else { return nil }
            self = .toolInputStart(
                toolCallID: toolCallID, toolName: toolName,
                providerExecuted: wire["providerExecuted"]?.boolValue,
                dynamic: wire["dynamic"]?.boolValue
            )
        case "tool-input-delta":
            guard let toolCallID = wire["toolCallId"]?.stringValue,
                  let inputTextDelta = wire["inputTextDelta"]?.stringValue else { return nil }
            self = .toolInputDelta(toolCallID: toolCallID, inputTextDelta: inputTextDelta)
        case "tool-input-available":
            guard let toolCallID = wire["toolCallId"]?.stringValue,
                  let toolName = wire["toolName"]?.stringValue else { return nil }
            self = .toolInputAvailable(
                toolCallID: toolCallID, toolName: toolName,
                input: wire["input"] ?? .null,
                providerExecuted: wire["providerExecuted"]?.boolValue,
                dynamic: wire["dynamic"]?.boolValue
            )
        case "tool-input-error":
            guard let toolCallID = wire["toolCallId"]?.stringValue,
                  let toolName = wire["toolName"]?.stringValue,
                  let errorText = wire["errorText"]?.stringValue else { return nil }
            self = .toolInputError(
                toolCallID: toolCallID, toolName: toolName,
                input: wire["input"], errorText: errorText,
                dynamic: wire["dynamic"]?.boolValue
            )
        case "tool-output-available":
            guard let toolCallID = wire["toolCallId"]?.stringValue else { return nil }
            self = .toolOutputAvailable(
                toolCallID: toolCallID,
                output: wire["output"] ?? .null,
                providerExecuted: wire["providerExecuted"]?.boolValue,
                preliminary: wire["preliminary"]?.boolValue,
                dynamic: wire["dynamic"]?.boolValue
            )
        case "tool-output-error":
            guard let toolCallID = wire["toolCallId"]?.stringValue,
                  let errorText = wire["errorText"]?.stringValue else { return nil }
            self = .toolOutputError(
                toolCallID: toolCallID, errorText: errorText,
                dynamic: wire["dynamic"]?.boolValue
            )
        case "tool-approval-request":
            guard let approvalID = wire["approvalId"]?.stringValue,
                  let toolCallID = wire["toolCallId"]?.stringValue else { return nil }
            self = .toolApprovalRequest(approvalID: approvalID, toolCallID: toolCallID)
        case "tool-approval-response":
            guard let approvalID = wire["approvalId"]?.stringValue,
                  let approved = wire["approved"]?.boolValue else { return nil }
            self = .toolApprovalResponse(
                approvalID: approvalID, approved: approved,
                reason: wire["reason"]?.stringValue
            )
        case "tool-output-denied":
            guard let toolCallID = wire["toolCallId"]?.stringValue else { return nil }
            self = .toolOutputDenied(toolCallID: toolCallID)
        case "source-url":
            guard let sourceID = wire["sourceId"]?.stringValue,
                  let url = wire["url"]?.stringValue else { return nil }
            self = .sourceURL(sourceID: sourceID, url: url, title: wire["title"]?.stringValue)
        case "source-document":
            guard let sourceID = wire["sourceId"]?.stringValue,
                  let mediaType = wire["mediaType"]?.stringValue,
                  let title = wire["title"]?.stringValue else { return nil }
            self = .sourceDocument(
                sourceID: sourceID, mediaType: mediaType, title: title,
                filename: wire["filename"]?.stringValue
            )
        case "file":
            guard let url = wire["url"]?.stringValue,
                  let mediaType = wire["mediaType"]?.stringValue else { return nil }
            self = .file(url: url, mediaType: mediaType)
        case "start-step":
            self = .startStep
        case "finish-step":
            self = .finishStep
        case "start":
            self = .start(
                messageID: wire["messageId"]?.stringValue,
                messageMetadata: wire["messageMetadata"]
            )
        case "finish":
            self = .finish(
                finishReason: wire["finishReason"]?.stringValue.flatMap(FinishReason.init(wireValue:)),
                messageMetadata: wire["messageMetadata"]
            )
        case "abort":
            self = .abort(reason: wire["reason"]?.stringValue)
        case "message-metadata":
            guard let metadata = wire["messageMetadata"] else { return nil }
            self = .messageMetadata(metadata)
        default:
            if type.hasPrefix("data-") {
                self = .data(
                    name: String(type.dropFirst("data-".count)),
                    id: wire["id"]?.stringValue,
                    data: wire["data"] ?? .null,
                    transient: wire["transient"]?.boolValue
                )
            } else {
                return nil
            }
        }
    }
}

extension UIMessageChunk: Codable {
    public init(from decoder: Decoder) throws {
        let raw = try JSONValue(from: decoder)
        guard let chunk = UIMessageChunk(wire: raw) else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: decoder.codingPath,
                debugDescription: "Unknown UI message chunk: \(raw)"
            ))
        }
        self = chunk
    }

    public func encode(to encoder: Encoder) throws {
        try wire.encode(to: encoder)
    }
}
