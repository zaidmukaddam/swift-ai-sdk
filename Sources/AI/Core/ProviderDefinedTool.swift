import Foundation

public struct ProviderDefinedTool: AIToolProtocol {
    public let provider: String
    public let id: String
    public let name: String
    public let args: JSONValue

    public var description: String { "" }
    public var parameters: JSONValue { .object([:]) }
    public var hasExecutor: Bool { false }

    public init(provider: String, id: String, name: String, args: JSONValue) {
        self.provider = provider
        self.id = id
        self.name = name
        self.args = args
    }

    public func execute(_ arguments: JSONValue) async throws -> JSONValue {
        throw AIError.invalidRequest(
            "Provider-defined tool '\(name)' (\(id)) is executed by the provider "
                + "and cannot be run client-side."
        )
    }
}

public extension LanguageModelRequest {
    var functionTools: [any AIToolProtocol] {
        tools.filter { !($0 is ProviderDefinedTool) }
    }

    func providerToolEntries(for provider: String) -> [JSONValue] {
        tools.compactMap { $0 as? ProviderDefinedTool }
            .filter { $0.provider == provider }
            .map(\.args)
    }

    func providerTools(for provider: String) -> [ProviderDefinedTool] {
        tools.compactMap { $0 as? ProviderDefinedTool }.filter { $0.provider == provider }
    }
}
