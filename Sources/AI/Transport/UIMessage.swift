import Foundation

public enum UIRole: String, Sendable, Codable, Hashable {
    case system
    case user
    case assistant
}

public enum UIPartState: String, Sendable, Codable, Hashable {
    case streaming
    case done
}

public enum UIToolState: String, Sendable, Codable, Hashable {
    case inputStreaming = "input-streaming"
    case inputAvailable = "input-available"
    case approvalRequested = "approval-requested"
    case approvalResponded = "approval-responded"
    case outputAvailable = "output-available"
    case outputError = "output-error"
    case outputDenied = "output-denied"
}

public struct ToolApproval: Sendable, Hashable {
    public var id: String
    public var approved: Bool?
    public var reason: String?

    public init(id: String, approved: Bool? = nil, reason: String? = nil) {
        self.id = id
        self.approved = approved
        self.reason = reason
    }
}

public struct UIMessage: Sendable, Hashable, Identifiable {
    public var id: String
    public var role: UIRole
    public var metadata: JSONValue?
    public var parts: [UIPart]

    public init(
        id: String = UUID().uuidString,
        role: UIRole,
        metadata: JSONValue? = nil,
        parts: [UIPart]
    ) {
        self.id = id
        self.role = role
        self.metadata = metadata
        self.parts = parts
    }

    public static func user(_ text: String, id: String = UUID().uuidString) -> UIMessage {
        UIMessage(id: id, role: .user, parts: [.text(TextUIPart(text: text))])
    }

    public static func assistant(_ text: String, id: String = UUID().uuidString) -> UIMessage {
        UIMessage(id: id, role: .assistant, parts: [.text(TextUIPart(text: text))])
    }

    public var text: String {
        parts.compactMap {
            if case .text(let part) = $0 { return part.text } else { return nil }
        }.joined()
    }
}

public enum UIPart: Sendable, Hashable {
    case text(TextUIPart)
    case reasoning(ReasoningUIPart)
    case tool(ToolUIPart)
    case sourceURL(SourceURLUIPart)
    case sourceDocument(SourceDocumentUIPart)
    case file(FileUIPart)
    case data(DataUIPart)
    case stepStart
}

public struct TextUIPart: Sendable, Hashable {
    public var text: String
    public var state: UIPartState?

    public init(text: String, state: UIPartState? = nil) {
        self.text = text
        self.state = state
    }
}

public struct ReasoningUIPart: Sendable, Hashable {
    public var text: String
    public var state: UIPartState?

    public init(text: String, state: UIPartState? = nil) {
        self.text = text
        self.state = state
    }
}

public struct ToolUIPart: Sendable, Hashable {
    public var toolName: String
    public var toolCallID: String
    public var state: UIToolState
    public var input: JSONValue?
    public var output: JSONValue?
    public var errorText: String?
    public var providerExecuted: Bool?
    public var isDynamic: Bool
    public var approval: ToolApproval?

    public init(
        toolName: String,
        toolCallID: String,
        state: UIToolState,
        input: JSONValue? = nil,
        output: JSONValue? = nil,
        errorText: String? = nil,
        providerExecuted: Bool? = nil,
        isDynamic: Bool = false,
        approval: ToolApproval? = nil
    ) {
        self.toolName = toolName
        self.toolCallID = toolCallID
        self.state = state
        self.input = input
        self.output = output
        self.errorText = errorText
        self.providerExecuted = providerExecuted
        self.isDynamic = isDynamic
        self.approval = approval
    }
}

public struct SourceURLUIPart: Sendable, Hashable {
    public var sourceID: String
    public var url: String
    public var title: String?

    public init(sourceID: String, url: String, title: String? = nil) {
        self.sourceID = sourceID
        self.url = url
        self.title = title
    }
}

public struct SourceDocumentUIPart: Sendable, Hashable {
    public var sourceID: String
    public var mediaType: String
    public var title: String
    public var filename: String?

    public init(sourceID: String, mediaType: String, title: String, filename: String? = nil) {
        self.sourceID = sourceID
        self.mediaType = mediaType
        self.title = title
        self.filename = filename
    }
}

public struct FileUIPart: Sendable, Hashable {
    public var url: String
    public var mediaType: String
    public var filename: String?

    public init(url: String, mediaType: String, filename: String? = nil) {
        self.url = url
        self.mediaType = mediaType
        self.filename = filename
    }
}

public struct DataUIPart: Sendable, Hashable {
    public var name: String
    public var id: String?
    public var data: JSONValue

    public init(name: String, id: String? = nil, data: JSONValue) {
        self.name = name
        self.id = id
        self.data = data
    }
}

extension UIMessage: Codable {
    public init(from decoder: Decoder) throws {
        let raw = try JSONValue(from: decoder)
        guard let message = UIMessage(wire: raw) else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: decoder.codingPath,
                debugDescription: "Invalid UIMessage: \(raw)"
            ))
        }
        self = message
    }

    public func encode(to encoder: Encoder) throws {
        try wire.encode(to: encoder)
    }

    public var wire: JSONValue {
        var object: [String: JSONValue] = [
            "id": .string(id),
            "role": .string(role.rawValue),
            "parts": .array(parts.map(\.wire))
        ]
        if let metadata { object["metadata"] = metadata }
        return .object(object)
    }

    public init?(wire: JSONValue) {
        guard let id = wire["id"]?.stringValue,
              let roleRaw = wire["role"]?.stringValue,
              let role = UIRole(rawValue: roleRaw),
              let partValues = wire["parts"]?.arrayValue
        else { return nil }
        self.init(
            id: id,
            role: role,
            metadata: wire["metadata"],
            parts: partValues.compactMap { UIPart(wire: $0) }
        )
    }
}

extension UIPart {
    public var wire: JSONValue {
        switch self {
        case .text(let part):
            var object: [String: JSONValue] = ["type": "text", "text": .string(part.text)]
            if let state = part.state { object["state"] = .string(state.rawValue) }
            return .object(object)

        case .reasoning(let part):
            var object: [String: JSONValue] = ["type": "reasoning", "text": .string(part.text)]
            if let state = part.state { object["state"] = .string(state.rawValue) }
            return .object(object)

        case .tool(let part):
            var object: [String: JSONValue] = [
                "toolCallId": .string(part.toolCallID),
                "state": .string(part.state.rawValue)
            ]
            if part.isDynamic {
                object["type"] = "dynamic-tool"
                object["toolName"] = .string(part.toolName)
            } else {
                object["type"] = .string("tool-\(part.toolName)")
            }
            if let input = part.input { object["input"] = input }
            if let output = part.output { object["output"] = output }
            if let errorText = part.errorText { object["errorText"] = .string(errorText) }
            if let providerExecuted = part.providerExecuted {
                object["providerExecuted"] = .bool(providerExecuted)
            }
            if let approval = part.approval {
                var payload: [String: JSONValue] = ["id": .string(approval.id)]
                if let approved = approval.approved { payload["approved"] = .bool(approved) }
                if let reason = approval.reason { payload["reason"] = .string(reason) }
                object["approval"] = .object(payload)
            }
            return .object(object)

        case .sourceURL(let part):
            var object: [String: JSONValue] = [
                "type": "source-url",
                "sourceId": .string(part.sourceID),
                "url": .string(part.url)
            ]
            if let title = part.title { object["title"] = .string(title) }
            return .object(object)

        case .sourceDocument(let part):
            var object: [String: JSONValue] = [
                "type": "source-document",
                "sourceId": .string(part.sourceID),
                "mediaType": .string(part.mediaType),
                "title": .string(part.title)
            ]
            if let filename = part.filename { object["filename"] = .string(filename) }
            return .object(object)

        case .file(let part):
            var object: [String: JSONValue] = [
                "type": "file",
                "url": .string(part.url),
                "mediaType": .string(part.mediaType)
            ]
            if let filename = part.filename { object["filename"] = .string(filename) }
            return .object(object)

        case .data(let part):
            var object: [String: JSONValue] = [
                "type": .string("data-\(part.name)"),
                "data": part.data
            ]
            if let id = part.id { object["id"] = .string(id) }
            return .object(object)

        case .stepStart:
            return .object(["type": "step-start"])
        }
    }

    public init?(wire: JSONValue) {
        guard let type = wire["type"]?.stringValue else { return nil }
        switch type {
        case "text":
            guard let text = wire["text"]?.stringValue else { return nil }
            self = .text(TextUIPart(
                text: text,
                state: wire["state"]?.stringValue.flatMap(UIPartState.init(rawValue:))
            ))
        case "reasoning":
            guard let text = wire["text"]?.stringValue else { return nil }
            self = .reasoning(ReasoningUIPart(
                text: text,
                state: wire["state"]?.stringValue.flatMap(UIPartState.init(rawValue:))
            ))
        case "dynamic-tool":
            guard let part = ToolUIPart(wire: wire, toolName: wire["toolName"]?.stringValue, isDynamic: true)
            else { return nil }
            self = .tool(part)
        case "source-url":
            guard let sourceID = wire["sourceId"]?.stringValue,
                  let url = wire["url"]?.stringValue else { return nil }
            self = .sourceURL(SourceURLUIPart(
                sourceID: sourceID, url: url, title: wire["title"]?.stringValue
            ))
        case "source-document":
            guard let sourceID = wire["sourceId"]?.stringValue,
                  let mediaType = wire["mediaType"]?.stringValue,
                  let title = wire["title"]?.stringValue else { return nil }
            self = .sourceDocument(SourceDocumentUIPart(
                sourceID: sourceID, mediaType: mediaType, title: title,
                filename: wire["filename"]?.stringValue
            ))
        case "file":
            guard let url = wire["url"]?.stringValue,
                  let mediaType = wire["mediaType"]?.stringValue else { return nil }
            self = .file(FileUIPart(
                url: url, mediaType: mediaType, filename: wire["filename"]?.stringValue
            ))
        case "step-start":
            self = .stepStart
        default:
            if type.hasPrefix("tool-") {
                guard let part = ToolUIPart(
                    wire: wire, toolName: String(type.dropFirst("tool-".count)), isDynamic: false
                ) else { return nil }
                self = .tool(part)
            } else if type.hasPrefix("data-") {
                self = .data(DataUIPart(
                    name: String(type.dropFirst("data-".count)),
                    id: wire["id"]?.stringValue,
                    data: wire["data"] ?? .null
                ))
            } else {
                return nil
            }
        }
    }
}

private extension ToolUIPart {
    init?(wire: JSONValue, toolName: String?, isDynamic: Bool) {
        guard let toolName,
              let toolCallID = wire["toolCallId"]?.stringValue,
              let stateRaw = wire["state"]?.stringValue,
              let state = UIToolState(rawValue: stateRaw)
        else { return nil }
        var approval: ToolApproval?
        if let payload = wire["approval"], let id = payload["id"]?.stringValue {
            approval = ToolApproval(
                id: id,
                approved: payload["approved"]?.boolValue,
                reason: payload["reason"]?.stringValue
            )
        }
        self.init(
            toolName: toolName,
            toolCallID: toolCallID,
            state: state,
            input: wire["input"],
            output: wire["output"],
            errorText: wire["errorText"]?.stringValue,
            providerExecuted: wire["providerExecuted"]?.boolValue,
            isDynamic: isDynamic,
            approval: approval
        )
    }
}
