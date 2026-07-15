import Foundation

public struct ToolCall: Sendable, Hashable, Identifiable {
    public var id: String
    public var name: String
    public var arguments: JSONValue
    public var providerExecuted: Bool

    public init(id: String, name: String, arguments: JSONValue, providerExecuted: Bool = false) {
        self.id = id
        self.name = name
        self.arguments = arguments
        self.providerExecuted = providerExecuted
    }
}

public struct ToolResult: Sendable, Hashable {
    public var toolCallID: String
    public var name: String
    public var output: JSONValue
    public var content: [ContentPart]?
    public var isError: Bool
    public var denied: Bool

    public init(
        toolCallID: String, name: String, output: JSONValue,
        content: [ContentPart]? = nil,
        isError: Bool = false, denied: Bool = false
    ) {
        self.toolCallID = toolCallID
        self.name = name
        self.output = output
        self.content = content
        self.isError = isError
        self.denied = denied
    }
}

public protocol AIToolProtocol: Sendable {
    var name: String { get }
    var description: String { get }
    var parameters: JSONValue { get }
    var hasExecutor: Bool { get }
    func needsApproval(_ arguments: JSONValue) async -> Bool
    func execute(_ arguments: JSONValue) async throws -> JSONValue
    func execute(_ arguments: JSONValue, options: ToolExecutionOptions) async throws -> JSONValue
    func toModelOutput(_ output: JSONValue) -> [ContentPart]?
}

public struct ToolExecutionOptions: Sendable {
    public var toolCallID: String
    public var messages: [Message]
    public var context: JSONValue?

    public init(toolCallID: String, messages: [Message] = [], context: JSONValue? = nil) {
        self.toolCallID = toolCallID
        self.messages = messages
        self.context = context
    }
}

public extension AIToolProtocol {
    var hasExecutor: Bool { true }
    func needsApproval(_ arguments: JSONValue) async -> Bool { false }
    func execute(
        _ arguments: JSONValue, options: ToolExecutionOptions
    ) async throws -> JSONValue {
        try await execute(arguments)
    }
    func toModelOutput(_ output: JSONValue) -> [ContentPart]? { nil }
}

public struct Tool: AIToolProtocol {
    public let name: String
    public let description: String
    public let parameters: JSONValue
    private let run: (@Sendable (JSONValue) async throws -> JSONValue)?
    private let contextualRun: (@Sendable (JSONValue, ToolExecutionOptions) async throws -> JSONValue)?
    private let approvalCheck: (@Sendable (JSONValue) async -> Bool)?
    public var modelOutput: (@Sendable (JSONValue) -> [ContentPart]?)? = nil

    public var hasExecutor: Bool { run != nil || contextualRun != nil }

    public func toModelOutput(_ output: JSONValue) -> [ContentPart]? {
        if let modelOutput { return modelOutput(output) }
        return nil
    }

    public init(
        name: String,
        description: String,
        parameters: JSONValue,
        needsApproval: Bool = false,
        execute: @escaping @Sendable (JSONValue, ToolExecutionOptions) async throws -> JSONValue
    ) {
        self.name = name
        self.description = description
        self.parameters = parameters
        self.run = nil
        self.contextualRun = execute
        self.approvalCheck = needsApproval ? { @Sendable _ in true } : nil
    }

    public init(
        name: String,
        description: String,
        parameters: JSONValue,
        needsApproval: Bool = false,
        execute: @escaping @Sendable (JSONValue) async throws -> JSONValue
    ) {
        self.name = name
        self.description = description
        self.parameters = parameters
        self.run = execute
        self.contextualRun = nil
        self.approvalCheck = needsApproval ? { @Sendable _ in true } : nil
    }

    public init(
        name: String,
        description: String,
        parameters: JSONValue,
        needsApproval: @escaping @Sendable (JSONValue) async -> Bool,
        execute: @escaping @Sendable (JSONValue) async throws -> JSONValue
    ) {
        self.name = name
        self.description = description
        self.parameters = parameters
        self.run = execute
        self.contextualRun = nil
        self.approvalCheck = needsApproval
    }

    public init(
        name: String,
        description: String,
        parameters: JSONValue
    ) {
        self.name = name
        self.description = description
        self.parameters = parameters
        self.run = nil
        self.contextualRun = nil
        self.approvalCheck = nil
    }

    public func needsApproval(_ arguments: JSONValue) async -> Bool {
        await approvalCheck?(arguments) ?? false
    }

    public func execute(_ arguments: JSONValue) async throws -> JSONValue {
        try await execute(arguments, options: ToolExecutionOptions(toolCallID: ""))
    }

    public func execute(
        _ arguments: JSONValue, options: ToolExecutionOptions
    ) async throws -> JSONValue {
        if let contextualRun { return try await contextualRun(arguments, options) }
        guard let run else { throw AIError.unknownTool(name) }
        return try await run(arguments)
    }
}

public extension Tool {
    static func typed<Args: Decodable & Sendable>(
        name: String,
        description: String,
        parameters: JSONValue,
        argumentsType: Args.Type = Args.self,
        execute: @escaping @Sendable (Args) async throws -> JSONValue
    ) -> Tool {
        Tool(name: name, description: description, parameters: parameters) { raw in
            let args = try raw.decode(Args.self)
            return try await execute(args)
        }
    }
}
