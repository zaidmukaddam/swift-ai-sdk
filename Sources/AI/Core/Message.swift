import Foundation

public enum Role: String, Sendable, Codable, Hashable {
    case system
    case user
    case assistant
    case tool
}

public enum ContentPart: Sendable, Hashable {
    case text(String)
    case image(ImageContent)
    case file(FileContent)
    case toolCall(ToolCall)
    case toolResult(ToolResult)
    case toolApprovalResponse(ToolApprovalResponse)
}

public struct ToolApprovalResponse: Sendable, Hashable {
    public var approvalID: String
    public var toolCallID: String
    public var approved: Bool
    public var reason: String?

    public init(approvalID: String, toolCallID: String, approved: Bool, reason: String? = nil) {
        self.approvalID = approvalID
        self.toolCallID = toolCallID
        self.approved = approved
        self.reason = reason
    }
}

public struct ImageContent: Sendable, Hashable {
    public var data: Data?
    public var url: URL?
    public var mediaType: String?

    public init(data: Data, mediaType: String? = nil) {
        self.data = data
        self.url = nil
        self.mediaType = mediaType
    }

    public init(url: URL, mediaType: String? = nil) {
        self.data = nil
        self.url = url
        self.mediaType = mediaType
    }
}

public struct FileContent: Sendable, Hashable {
    public var data: Data?
    public var url: URL?
    public var mediaType: String
    public var filename: String?

    public init(data: Data, mediaType: String, filename: String? = nil) {
        self.data = data
        self.url = nil
        self.mediaType = mediaType
        self.filename = filename
    }

    public init(url: URL, mediaType: String, filename: String? = nil) {
        self.data = nil
        self.url = url
        self.mediaType = mediaType
        self.filename = filename
    }
}

extension ImageContent {
    var resolvedMediaType: String {
        if let mediaType, mediaType.contains("/") { return mediaType }
        if let data, let detected = ImageContent.detectMediaType(data) { return detected }
        return "image/jpeg"
    }

    static func detectMediaType(_ data: Data) -> String? {
        let signatures: [(prefix: [UInt8], mediaType: String)] = [
            ([0x47, 0x49, 0x46], "image/gif"),
            ([0x89, 0x50, 0x4E, 0x47], "image/png"),
            ([0xFF, 0xD8], "image/jpeg")
        ]
        for (prefix, mediaType) in signatures where data.starts(with: prefix) {
            return mediaType
        }
        if data.count >= 12, data.starts(with: [0x52, 0x49, 0x46, 0x46]),
           data.dropFirst(8).starts(with: [0x57, 0x45, 0x42, 0x50]) {
            return "image/webp"
        }
        return nil
    }
}

public struct Message: Sendable, Hashable {
    public var role: Role
    public var content: [ContentPart]

    public init(role: Role, content: [ContentPart]) {
        self.role = role
        self.content = content
    }

    public static func system(_ text: String) -> Message { .init(role: .system, content: [.text(text)]) }
    public static func user(_ text: String) -> Message { .init(role: .user, content: [.text(text)]) }
    public static func assistant(_ text: String) -> Message { .init(role: .assistant, content: [.text(text)]) }

    public static func user(_ text: String, images: [ImageContent]) -> Message {
        .init(role: .user, content: [.text(text)] + images.map { .image($0) })
    }

    public var text: String {
        content.compactMap { if case .text(let t) = $0 { return t } else { return nil } }
            .joined()
    }
}

public struct Usage: Sendable, Hashable, Codable {
    public var inputTokens: Int
    public var outputTokens: Int
    public var cachedInputTokens: Int?
    public var reasoningTokens: Int?
    public var totalTokens: Int { inputTokens + outputTokens }

    public init(
        inputTokens: Int = 0,
        outputTokens: Int = 0,
        cachedInputTokens: Int? = nil,
        reasoningTokens: Int? = nil
    ) {
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.cachedInputTokens = cachedInputTokens
        self.reasoningTokens = reasoningTokens
    }

    static func + (lhs: Usage, rhs: Usage) -> Usage {
        func addOptional(_ a: Int?, _ b: Int?) -> Int? {
            if a == nil && b == nil { return nil }
            return (a ?? 0) + (b ?? 0)
        }
        return Usage(
            inputTokens: lhs.inputTokens + rhs.inputTokens,
            outputTokens: lhs.outputTokens + rhs.outputTokens,
            cachedInputTokens: addOptional(lhs.cachedInputTokens, rhs.cachedInputTokens),
            reasoningTokens: addOptional(lhs.reasoningTokens, rhs.reasoningTokens)
        )
    }
}

public enum FinishReason: String, Sendable, Codable, Hashable {
    case stop
    case length
    case toolCalls
    case contentFilter
    case error
    case other
}
