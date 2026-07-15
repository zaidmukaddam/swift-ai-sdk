import Foundation

public struct MCPToolFingerprint: Sendable, Equatable {
    public let name: String
    public let description: String
    public let schema: String

    public init(name: String, description: String, schema: String) {
        self.name = name
        self.description = description
        self.schema = schema
    }
}

public struct MCPToolDrift: Sendable, Equatable {
    public let added: [String]
    public let removed: [String]
    public let changed: [String]

    public var hasDrift: Bool { !added.isEmpty || !removed.isEmpty || !changed.isEmpty }
}

public func fingerprintTools(_ tools: [any AIToolProtocol]) -> [String: MCPToolFingerprint] {
    var map: [String: MCPToolFingerprint] = [:]
    for tool in tools {
        map[tool.name] = MCPToolFingerprint(
            name: tool.name,
            description: tool.description,
            schema: canonicalJSON(tool.parameters)
        )
    }
    return map
}

public func detectToolDrift(
    _ current: [String: MCPToolFingerprint],
    baseline: [String: MCPToolFingerprint]
) -> MCPToolDrift {
    var added: [String] = []
    var removed: [String] = []
    var changed: [String] = []
    for name in current.keys where baseline[name] == nil { added.append(name) }
    for name in baseline.keys where current[name] == nil { removed.append(name) }
    for (name, fingerprint) in current {
        if let base = baseline[name], base != fingerprint { changed.append(name) }
    }
    return MCPToolDrift(
        added: added.sorted(),
        removed: removed.sorted(),
        changed: changed.sorted()
    )
}

private func canonicalJSON(_ value: JSONValue) -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    if let data = try? encoder.encode(value) {
        return String(decoding: data, as: UTF8.self)
    }
    return String(describing: value)
}
